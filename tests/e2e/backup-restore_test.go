/*
Copyright © 2024 SUSE LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package e2e_test

import (
	"os"
	"os/exec"
	"strings"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"github.com/rancher-sandbox/ele-testhelpers/kubectl"
	"github.com/rancher-sandbox/ele-testhelpers/tools"
)

const (
	backupResourceName  = "elemental-backup"
	restoreResourceName = "elemental-restore"
)

var _ = Describe("E2E - Install Backup/Restore Operator", Label("install-backup-restore"), func() {
	// Create kubectl context
	// Default timeout is too small, so New() cannot be used
	k := &kubectl.Kubectl{
		Namespace:    "",
		PollTimeout:  tools.SetTimeout(300 * time.Second),
		PollInterval: 500 * time.Millisecond,
	}

	It("Install Backup/Restore Operator", func() {
		// Report to Qase
		testCaseID = 64

		By("Installing rancher-backup-operator", func() {
			InstallBackupOperator(k)
		})
	})
})

var _ = Describe("E2E - Test full Backup/Restore", Label("test-full-backup-restore"), func() {
	// Create kubectl context
	// Default timeout is too small, so New() cannot be used
	k := &kubectl.Kubectl{
		Namespace:    "",
		PollTimeout:  tools.SetTimeout(300 * time.Second),
		PollInterval: 500 * time.Millisecond,
	}

	var backupFile string

	It("Do a full backup/restore test", func() {
		// TODO: use another case id for full backup/restore test
		// Report to Qase
		// testCaseID = 65

		By("Adding a backup resource", func() {
			err := kubectl.Apply(clusterNS, backupYaml)
			Expect(err).To(Not(HaveOccurred()))
		})

		By("Checking that the backup has been done", func() {
			out, err := kubectl.RunWithoutErr("get", "backup", backupResourceName,
				"-o", "jsonpath={.metadata.name}")
			Expect(err).To(Not(HaveOccurred()))
			Expect(out).To(ContainSubstring(backupResourceName))

			// Wait for backup to be done
			CheckBackupRestore("Done with backup")
		})

		By("Copying the backup file", func() {
			// Get local storage path
			localPath := GetBackupDir()

			// Get the backup file from the previous backup
			file, err := kubectl.RunWithoutErr("get", "backup", backupResourceName, "-o", "jsonpath={.status.filename}")
			Expect(err).To(Not(HaveOccurred()))

			// Share the filename across other functions
			backupFile = file

			// Copy backup file
			err = exec.Command("sudo", "cp", localPath+"/"+backupFile, ".").Run()
			Expect(err).To(Not(HaveOccurred()))
		})

		By("Uninstalling K8s", func() {
			if strings.Contains(k8sUpstreamVersion, "rke2") {
				out, err := exec.Command("sudo", "/usr/local/bin/rke2-uninstall.sh").CombinedOutput()
				Expect(err).To(Not(HaveOccurred()), out)
			} else {
				out, err := exec.Command("k3s-uninstall.sh").CombinedOutput()
				Expect(err).To(Not(HaveOccurred()), out)
			}
		})

		if strings.Contains(k8sUpstreamVersion, "rke2") {
			By("Installing RKE2", func() {
				InstallRKE2()
			})

			// Use the new Kube config
			err := os.Setenv("KUBECONFIG", "/etc/rancher/rke2/rke2.yaml")
			Expect(err).To(Not(HaveOccurred()))

			By("Starting RKE2", func() {
				StartRKE2()
			})

			By("Waiting for RKE2 to be started", func() {
				WaitForRKE2(k)
			})

			By("Installing local-path-provisionner", func() {
				InstallLocalStorage(k)
			})
		} else {
			By("Installing K3s", func() {
				InstallK3s()
			})

			// Use the new Kube config
			err := os.Setenv("KUBECONFIG", "/etc/rancher/k3s/k3s.yaml")
			Expect(err).To(Not(HaveOccurred()))

			By("Starting K3s", func() {
				StartK3s()
			})

			By("Waiting for K3s to be started", func() {
				WaitForK3s(k)
			})
		}

		By("Installing rancher-backup-operator", func() {
			InstallBackupOperator(k)
		})

		By("Copying backup file to restore", func() {
			// Get new local storage path
			localPath := GetBackupDir()

			// Copy backup file
			err := exec.Command("sudo", "cp", backupFile, localPath).Run()
			Expect(err).To(Not(HaveOccurred()))
		})

		By("Adding a restore resource", func() {
			// Set the backup file in the restore resource
			err := tools.Sed("%BACKUP_FILE%", backupFile, restoreYaml)
			Expect(err).To(Not(HaveOccurred()))

			// "prune" option should be set to false in case of migration test
			err = tools.Sed("%PRUNE%", "false", restoreYaml)
			Expect(err).To(Not(HaveOccurred()))

			// And apply
			err = kubectl.Apply(clusterNS, restoreYaml)
			Expect(err).To(Not(HaveOccurred()))
		})

		By("Checking that the restore has been done", func() {
			// Wait until resources are available again
			Eventually(func() string {
				out, _ := kubectl.RunWithoutErr("get", "restore", restoreResourceName,
					"-o", "jsonpath={.metadata.name}")
				return out
			}, tools.SetTimeout(5*time.Minute), 10*time.Second).Should(ContainSubstring(restoreResourceName))

			// Wait for restore to be done
			CheckBackupRestore("Done restoring")
		})

		By("Installing CertManager", func() {
			InstallCertManager(k)
		})

		By("Installing Rancher Manager", func() {
			InstallRancher(k)
		})

		By("Upgrading/re-installing Elemental Operator", func() {
			installOrder := []string{"elemental-operator-crds", "elemental-operator"}
			InstallElementalOperator(k, installOrder, operatorRepo)
		})

		By("Checking cluster state after restore", func() {
			WaitCluster(clusterNS, clusterName)
		})
	})
})

var _ = Describe("E2E - Test simple Backup/Restore", Label("test-simple-backup-restore"), func() {
	It("Do a backup", func() {
		// Report to Qase
		testCaseID = 65

		By("Adding a backup resource", func() {
			err := kubectl.Apply(clusterNS, backupYaml)
			Expect(err).To(Not(HaveOccurred()))
		})

		By("Checking that the backup has been done", func() {
			out, err := kubectl.RunWithoutErr("get", "backup", backupResourceName,
				"-o", "jsonpath={.metadata.name}")
			Expect(err).To(Not(HaveOccurred()))
			Expect(out).To(ContainSubstring(backupResourceName))

			// Wait for backup to be done
			CheckBackupRestore("Done with backup")
		})
	})

	It("Do a restore", func() {
		// Report to Qase
		testCaseID = 66

		By("Deleting some Elemental resources", func() {
			for _, obj := range []string{"MachineRegistration", "MachineInventorySelectorTemplate"} {
				// List the resources
				list, err := kubectl.RunWithoutErr("get", obj,
					"--namespace", clusterNS,
					"-o", "jsonpath={.items[*].metadata.name}")
				Expect(err).To(Not(HaveOccurred()))

				// Delete the resources
				for _, rsc := range strings.Split(list, " ") {
					_, err := kubectl.RunWithoutErr("delete", obj, "--namespace", clusterNS, rsc)
					Expect(err).To(Not(HaveOccurred()))
				}
			}
		})

		By("Adding a restore resource", func() {
			// Get the backup file from the previous backup
			backupFile, err := kubectl.RunWithoutErr("get", "backup", backupResourceName, "-o", "jsonpath={.status.filename}")
			Expect(err).To(Not(HaveOccurred()))

			// Set the backup file in the restore resource
			err = tools.Sed("%BACKUP_FILE%", backupFile, restoreYaml)
			Expect(err).To(Not(HaveOccurred()))

			// "prune" option should be set to true here
			err = tools.Sed("%PRUNE%", "true", restoreYaml)
			Expect(err).To(Not(HaveOccurred()))

			// And apply
			err = kubectl.Apply(clusterNS, restoreYaml)
			Expect(err).To(Not(HaveOccurred()))
		})

		By("Checking that the restore has been done", func() {
			// Wait until resources are available again
			Eventually(func() string {
				out, _ := kubectl.RunWithoutErr("get", "restore", restoreResourceName,
					"-o", "jsonpath={.metadata.name}")
				return out
			}, tools.SetTimeout(5*time.Minute), 10*time.Second).Should(ContainSubstring(restoreResourceName))

			// Wait for restore to be done
			CheckBackupRestore("Done restoring")
		})

		By("Checking cluster state after restore", func() {
			WaitCluster(clusterNS, clusterName)
		})
	})
})
