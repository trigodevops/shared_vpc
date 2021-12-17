locals {
  subnet_01 = "${var.network_name}-subnet-01"
  subnet_02 = "${var.network_name}-subnet-02"
}

/******************************************
  Host Project Creation
 *****************************************/
module "host-project" {
  source                         = "terraform-google-modules/project-factory/google"
  random_project_id              = true
  name                           = var.host_project_name
  org_id                         = var.organization_id
  folder_id                      = var.folder_id
  billing_account                = var.billing_account
  enable_shared_vpc_host_project = true
  default_network_tier           = var.default_network_tier
}

/******************************************
  Network Creation
 *****************************************/
module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 2.5.0"

  project_id                             = module.host-project.project_id
  network_name                           = var.network_name
  delete_default_internet_gateway_routes = true

  subnets = [
    {
      subnet_name   = local.subnet_01
      subnet_ip     = "10.1.0.0/16"
      subnet_region = "us-west1"
    },
    {
      subnet_name           = local.subnet_02
      subnet_ip             = "10.2.0.0/16"
      subnet_region         = "us-west1"
      subnet_private_access = true
      subnet_flow_logs      = true
    },
  ]

  secondary_ranges = {
    (local.subnet_01) = [
      {
        range_name    = "${local.subnet_01}-secondary"
        ip_cidr_range = "182.1.0.0/16"
      }
    ]

    (local.subnet_02) = [
      {
        range_name    = "${local.subnet_02}-secondary"
        ip_cidr_range = "182.2.0.0/16"
      },
    ]
  }
}

/******************************************
  Service Project Creation
 *****************************************/
module "service-project" {
  source = "terraform-google-modules/project-factory/google//modules/svpc_service_project"
  name              = "${var.service_project_name}-0001"
  random_project_id = false

  org_id          = var.organization_id
  folder_id       = var.folder_id
  billing_account = var.billing_account

  shared_vpc         = module.host-project.project_id
  shared_vpc_subnets = module.vpc.subnets_self_links

  activate_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "dataproc.googleapis.com",
    "dataflow.googleapis.com",
  ]

  disable_services_on_destroy = false
}

/******************************************
  Second Service Project Creation
 *****************************************/
module "service-project-b" {
  source = "terraform-google-modules/project-factory/google//modules/svpc_service_project"
  name              = "${var.service_project_name}-0002"
  random_project_id = false

  org_id          = var.organization_id
  folder_id       = var.folder_id
  billing_account = var.billing_account

  shared_vpc = module.host-project.project_id

  activate_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "dataproc.googleapis.com",
  ]

  activate_api_identities = [{
    api = "healthcare.googleapis.com"
    roles = [
      "roles/healthcare.serviceAgent",
      "roles/bigquery.jobUser",
    ]
  }]

  disable_services_on_destroy = false
}


resource "google_compute_instance" "inst1" {
  project      = module.service-project.project_id
  zone         = "${module.vpc.subnets_regions[0]}-a"
  name         = "inst1"
  machine_type = "e2-micro"
  network_interface {
    subnetwork   = module.vpc.subnets_self_links[0]
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-9"
    }
  }
}

resource "google_compute_instance" "inst2" {
  project      = module.service-project.project_id
  zone         = "${module.vpc.subnets_regions[1]}-a"
  name         = "inst2"
  machine_type = "e2-micro"
  network_interface {
    subnetwork   = module.vpc.subnets_self_links[1]
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-9"
    }
  }
}

