module github.com/rancher/elemental/tests

go 1.22.0

toolchain go1.22.7

replace go.qase.io/client => github.com/rancher/qase-go/client v0.0.0-20231114201952-65195ec001fa

require (
	github.com/onsi/ginkgo/v2 v2.20.2
	github.com/onsi/gomega v1.34.2
	github.com/rancher-sandbox/ele-testhelpers v0.0.0-20241112093046-812bbbbdb8e3
	github.com/rancher-sandbox/qase-ginkgo v1.0.1
	github.com/sirupsen/logrus v1.9.3
	golang.org/x/mod v0.21.0
	gopkg.in/yaml.v3 v3.0.1
)

require (
	github.com/antihax/optional v1.0.0 // indirect
	github.com/bramvdbogaerde/go-scp v1.5.0 // indirect
	github.com/go-logr/logr v1.4.2 // indirect
	github.com/go-task/slim-sprig/v3 v3.0.0 // indirect
	github.com/google/go-cmp v0.6.0 // indirect
	github.com/google/pprof v0.0.0-20240925223930-fa3061bff0bc // indirect
	github.com/pkg/errors v0.9.1 // indirect
	go.qase.io/client v0.0.0-20231114201952-65195ec001fa // indirect
	go.uber.org/multierr v1.11.0 // indirect
	go.uber.org/zap v1.27.0 // indirect
	golang.org/x/crypto v0.31.0 // indirect
	golang.org/x/net v0.29.0 // indirect
	golang.org/x/oauth2 v0.23.0 // indirect
	golang.org/x/sys v0.28.0 // indirect
	golang.org/x/text v0.21.0 // indirect
	golang.org/x/tools v0.25.0 // indirect
	google.golang.org/protobuf v1.34.2 // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
	libvirt.org/libvirt-go-xml v7.4.0+incompatible // indirect
)
