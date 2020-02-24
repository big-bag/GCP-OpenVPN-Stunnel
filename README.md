# About
This repository describes how to build an Alpine Linux image using a Packer, provision it using a Terraform and configure it using an Ansible on a free Compute Engine instance in the [Google Cloud Platform](https://cloud.google.com/free/).

Work environment: I prefer to have different working environments (virtual machines) for different tasks. Here I use CentOS 7 on remote server from where all commands execute.

* [Build image and upload to GCE](#build-image-and-upload-to-gce)
* [Provision GCE instance](#provision-gce-instance)
* [Configure GCE instance](#configure-gce-instance)
* [Configure client devices](#configure-client-devices)

# Build image and upload it to GCE
## Connect to remote server (work environment)
```
ssh -X -i ~/.path/id_rsa [USERNAME]@[EXTERNAL_IP_ADDRESS]
```
use flag -X to enabled X11 forwarding to connect to server by VNC on build stage (below)

## Install Packer
Download [precompiled Packer binary](https://packer.io/downloads.html) and unzip it
```
curl -O -L https://releases.hashicorp.com/packer/1.5.4/packer_1.5.4_linux_amd64.zip
```
```
sudo unzip packer_1.5.4_linux_amd64.zip -d /usr/local/bin/
```

## Create a Service Account
Go to [IAM & Admin → Service accounts](https://console.developers.google.com/iam-admin/serviceaccounts):
1. Service account name: e.g., Deploy service account
2. Service account ID: e.g., deploy-sa
3. Roles assigned to account:
    * Compute Engine → Compute Viewer         # using in Ansible dynamic inventory
    * Storage → Storage Object Creator        # using in packer to upload .tar.gz image archive into `Bucket`
    * Compute Engine → Compute Storage Admin  # using in packer to create image in `Compute Engine`
    * Storage → Storage Object Admin          # using in packer to delete .tar.gz image archive from `Bucket`
4. Create key → JSON

Download JSON credentials into `.secrets` folder

## Build and upload image
Validate
```
/usr/local/bin/packer validate alpine.json
```

Install dependencies
```
sudo yum install -y qemu-system-x86
```

Generate SSH keys
```
ssh-keygen -t rsa -f .secrets/id_rsa -C [USERNAME]
chmod 400 .secrets/id_rsa
```

Build
```
/usr/local/bin/packer build \
  -var-file=packer.vars.json \
  -var-file=terraform.tfvars.json \
  alpine.json
```
or run in debug mode
```
env PACKER_LOG=1 /usr/local/bin/packer build \
  -var-file=packer.vars.json \
  -var-file=terraform.tfvars.json \
  alpine.json
```

After build starts connect to remote server by VNC using 5901 port (optional)

Common variables for Packer and Terraform are stored in `terraform.tfvars.json`

Packer specific variables are stored in `packer.vars.json` and in `alpine.json`

After each Packer launch, variable `gcp_image` in `terraform.tfvars.json` will be updated. Then this variable will be used in Terraform

## Notes
When run locally on MacOS enable display and change hypervisor
```
{
  "builders": [
    {
      "type": "qemu",
      "vnc_bind_address": "127.0.0.1",
      "accelerator": "hvf"
    }
  ]
}
```

When run remotly with enabled X11 forwarding `ssh -X -i ...` enable display
```
{
  "builders": [
    {
      "type": "qemu",
      "vnc_bind_address": "0.0.0.0",
      "accelerator": "kvm",
    }
  ]
}
```

When run remotly with disabled X11 forwarding `ssh -i ...` disable display
```
{
  "builders": [
    {
      "type": "qemu",
      "headless": "true"
    }
  ]
}
```

This dirty code between `reboot` and login to system as `root`
```
{
  "builders": [
    {
      "boot_command": [
        "reboot<enter><wait20s>",
        "{{user `root_pass`}}<enter><wait15>",
        "<leftCtrlOn>c<leftCtrlOff><wait10>",
        "root<enter><wait>",
      ]
    }
  ]
}
```
is to avoid problem with long `Starting busybox crond` service after reboot.
Will be fixed later.

# Provision GCE instance
## Terraform
[Download](https://www.terraform.io/downloads.html) binary and unzip it
```
curl -O -L https://releases.hashicorp.com/terraform/0.12.21/terraform_0.12.21_linux_amd64.zip
```
```
sudo unzip terraform_0.12.21_linux_amd64.zip -d /usr/local/bin/
```

## Google Cloud SDK
Install
```
curl https://sdk.cloud.google.com | bash
```
Start a new shell for the changes to take effect
```
gcloud init --console-only
```
```
gcloud auth application-default login
```

Configure
Check current configuration
```
gcloud config list
```
Setup project
```
gcloud config set project [GCP_PROJECT_ID]
```
Setup region
```
gcloud compute regions list
gcloud config set compute/region us-east1
gcloud config list compute/region
```
Setup zone
```
gcloud compute zones list
gcloud config set compute/zone us-east1-b
gcloud config list compute/zone
```

## Terraform usage
Initialize Terraform to download the latest version of the Google provider
```
terraform init
```
Validate the configuration syntax and show a preview of what will be created
```
terraform plan
```
Apply those changes
```
terraform apply
```

## Check
Check connection to remote server
```
ssh -i .secrets/id_rsa [USERNAME]@[EXTERNAL_IP_ADDRESS]
```
or using gcloud console
```
gcloud compute ssh --ssh-key-file=.secrets/id_rsa [USERNAME]@instance-1
```

## Notes
1. Code
```
variable "user_name" {}
variable "user_pubkey" {}

[...]

resource "google_compute_project_metadata" "default" {
    metadata = {
        "ssh-keys" = "${var.user_name}:${file("${var.user_pubkey}")}"
    }

    project  = "${var.gcp_project}"
}
```
is not necessary when using Alpine Linux image. Because the public key of the user has already been added to the image.

But if you need to change the operating system, such as СentOS 7, these data need to be added to the [Metadata](https://console.cloud.google.com/compute/metadata/sshKeys).

2. To upgrade Terraform from v0.11 up to v0.12 push code to repository (for safety) and execute commands
```
terraform init
terraform 0.12upgrade
```

# Configure GCE instance
Install Ansible
```
sudo yum install -y epel-release
sudo yum install -y ansible
```

Install requirements for GCP modules
```
sudo yum install python2-pip
sudo pip install requests google-auth
```

Create dynamic inventory config in `inventory/inventory.gcp.yml` as in example below
```
---
plugin: gcp_compute
zones:
  - us-east1-b
projects:
  - [GCP_PROJECT_ID]
service_account_file: .secrets/[GCP_PROJECT_ID]-[SOME_ID].json
auth_kind: serviceaccount
scopes:
  - 'https://www.googleapis.com/auth/cloud-platform'
  - 'https://www.googleapis.com/auth/compute.readonly'
hostnames:
  - name
compose:
  ansible_host: networkInterfaces[0].accessConfigs[0].natIP
```

Create static inventory config in `inventory/inventory.yml` as in example below
```
---
all:
  vars:
    ansible_user: [USERNAME]
    ansible_ssh_private_key_file: .secrets/id_rsa
    ansible_python_interpreter: /usr/bin/python3
```

Check connection to remote server
```
ansible instance-1 -m ping -u [USERNAME] --key-file .secrets/id_rsa
```

Check dynamic inventory
```
ansible-inventory -i inventory.gcp.yml --list
ansible-inventory -i inventory.gcp.yml --graph
ansible all -m ping
ansible instance-1 -m setup
```

Create password for Ansible Vault in `.secrets/vault_pass`

Create vault
```
ansible-vault create host_vars/instance-1/vault.yml
```
and add vars as in example

Create dh.pem
```
openssl dhparam -out roles/openvpn/files/dh.pem 4096
```

Run roles
```
ansible-playbook site.yml
```

# Configure client devices

## Check iptables rules on Apline Linux server on GCE
Show iptables rules in all tables
```
sudo iptables -L -v
sudo iptables -t nat -L -v
sudo iptables -t mangle -L -v
```

## Configure MikroTik
### Import certificates
Using any sftp-client (e.g., FileZilla) create folder structure `certs/gcp` in Files and upload `ca.crt`, `router_01.crt`, `router_01.key`

Import certificates
```
/certificate import file-name=certs/gcp/ca.crt
/certificate import file-name=certs/gcp/router_01.crt
/certificate import file-name=certs/gcp/router_01.key
```
When a passphrase is requested just skip it (hit <Enter>)

Rename imported certificates
```
/certificate set ca.crt_0 name=gcp_ca.crt_0
/certificate set router_01.crt_0 name=gcp_router_01.crt_0
```
Check certificates
```
/certificate print
```
Important! Certificates must have flag `K`

### Setup OpenVPN network interface
```
/interface ovpn-client
add certificate=gcp_router_01.crt_0 \
    cipher=aes256 \
    comment="openvpn interface to gcp instance" \
    connect-to=[DOMAIN OR IP ADDRESS] \
    disabled=no \
    mode=ip \
    name=ovpn-client-gcp \
    password="[PASS FROM ANSIBLE VAULT]" \
    port=1194 \
    user=router_01
```
(Optional) configure DNS record on MikroTik if domain doesn't resolve
```
/ip dns static
add address=[IP-ADDRESS] name=[DOMAIN]
```
Check interface status and ensure that router received IP-address
```
/interface ovpn-client print
/ip address print
```

### Setup firewall
```
/ip firewall nat
add action=dst-nat \
    chain=dstnat \
    comment="allow http from vpn" \
    dst-port=80 \
    in-interface=ovpn-client-gcp \
    protocol=tcp \
    to-addresses=[IP-ADDRESS OF WEB SERVER] \
    to-ports=80
add action=dst-nat \
    chain=dstnat \
    comment="allow https from vpn" \
    dst-port=443 \
    in-interface=ovpn-client-gcp \
    protocol=tcp \
    to-addresses=[IP-ADDRESS OF WEB SERVER] \
    to-ports=443
add action=dst-nat \
    chain=dstnat \
    comment="allow rdp from vpn" \
    dst-port=3389 \
    in-interface=ovpn-client-gcp \
    protocol=tcp \
    to-addresses=[IP-ADDRESS OF WINDOWS SERVER] \
    to-ports=3389
add action=dst-nat \
    chain=dstnat \
    comment="allow smtp from vpn" \
    dst-port=25 \
    in-interface=ovpn-client-gcp \
    protocol=tcp \
    to-addresses=[IP-ADDRESS OF MAIL SERVER] \
    to-ports=25
add action=dst-nat \
    chain=dstnat \
    comment="allow imaps from vpn" \
    dst-port=993 \
    in-interface=ovpn-client-gcp \
    protocol=tcp \
    to-addresses=[IP-ADDRESS OF MAIL SERVER] \
    to-ports=993
add action=dst-nat \
    chain=dstnat \
    comment="allow smtps from vpn" \
    dst-port=465 \
    in-interface=ovpn-client-gcp \
    protocol=tcp \
    to-addresses=[IP-ADDRESS OF MAIL SERVER] \
    to-ports=465
```
