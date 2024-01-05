
resource "yandex_vpc_address" "custom_addr" {
  name = "exampleAddress"

  external_ipv4_address {
    zone_id = "ru-central1-c"
  }
}

locals {
  backend_instances  = [for v in yandex_compute_instance.backend : v.network_interface.0.nat_ip_address]
  nginx_instances    = [for v in yandex_compute_instance.nginx : v.network_interface.0.nat_ip_address]
  database_instances = [for v in yandex_compute_instance.database : v.network_interface.0.ip_address]
  database_ips       = "${yandex_compute_instance.database[0].network_interface.0.ip_address},${yandex_compute_instance.database[1].network_interface.0.ip_address},${yandex_compute_instance.database[2].network_interface.0.ip_address}"
  admin_instances    = yandex_compute_instance.admin.network_interface.0.nat_ip_address
}

resource "local_file" "hosts-ini" {
  filename = "hosts.ini"
  content = templatefile("hosts.tftpl", {
    backend_instances = local.backend_instances
    nginx_instances   = local.nginx_instances
    admin_instances   = local.admin_instances
  })
}

resource "local_file" "pg-inventory" {
  filename = "postgresql_cluster/inventory"
  content = templatefile("postgresql_cluster/inventory.tftpl", {
    database_instances = local.database_instances
    admin_instances    = local.admin_instances
  })
}


resource "yandex_compute_instance" "backend" {
  platform_id = "standard-v1"
  hostname    = "backend-${count.index}"
  count       = 2

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8idfolcq1l43h1mlft" # ОС (Ubuntu, 22.04 LTS)
    }

  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.custom_subnet.id
    security_group_ids = [yandex_vpc_security_group.custom_sg.id]
    nat                = true
  }

  metadata = {
    user-data = "#cloud-config\nusers:\n  - name: ubuntu\n    groups: sudo\n    shell: /bin/bash\n    sudo: 'ALL=(ALL) NOPASSWD:ALL'\n    ssh-authorized-keys:\n      - ${var.public_key}"
  }
}

resource "yandex_compute_instance" "database" {
  platform_id = "standard-v1"
  hostname    = "database-${count.index}"
  count       = 3

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8idfolcq1l43h1mlft" # ОС (Ubuntu, 22.04 LTS)
      size     = 25
    }

  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.custom_subnet.id
    security_group_ids = [yandex_vpc_security_group.custom_sg.id]
  }

  metadata = {
    user-data = "#cloud-config\nusers:\n  - name: ubuntu\n    groups: sudo\n    shell: /bin/bash\n    sudo: 'ALL=(ALL) NOPASSWD:ALL'\n    ssh-authorized-keys:\n      - ${var.public_key}"
  }
}

resource "yandex_compute_instance" "nginx" {
  platform_id = "standard-v1"
  hostname    = "nginx-${count.index}"
  count       = 2

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8idfolcq1l43h1mlft" # ОС (Ubuntu, 22.04 LTS)
    }

  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.custom_subnet.id
    security_group_ids = [yandex_vpc_security_group.custom_sg.id]
    nat                = true
  }

  metadata = {
    user-data = "#cloud-config\nusers:\n  - name: ubuntu\n    groups: sudo\n    shell: /bin/bash\n    sudo: 'ALL=(ALL) NOPASSWD:ALL'\n    ssh-authorized-keys:\n      - ${var.public_key}"
  }
}

resource "yandex_compute_instance" "admin" {
  platform_id = "standard-v1"
  hostname    = "admin"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd8idfolcq1l43h1mlft" # ОС (Ubuntu, 22.04 LTS)
    }

  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.custom_subnet.id
    security_group_ids = [yandex_vpc_security_group.custom_sg.id]
    nat                = true
  }

  metadata = {
    user-data = "#cloud-config\nusers:\n  - name: ubuntu\n    groups: sudo\n    shell: /bin/bash\n    sudo: 'ALL=(ALL) NOPASSWD:ALL'\n    ssh-authorized-keys:\n      - ${var.public_key}"
  }
}

resource "yandex_vpc_network" "custom_vpc" {
  name = "custom_vpc"

}
resource "yandex_vpc_subnet" "custom_subnet" {
  zone           = "ru-central1-c"
  network_id     = yandex_vpc_network.custom_vpc.id
  v4_cidr_blocks = ["10.5.0.0/24"]
  route_table_id = yandex_vpc_route_table.custom_nat_route_table.id
}

resource "yandex_vpc_security_group" "custom_sg" {
  name        = "WebServer security group"
  description = "My Security group"
  network_id  = yandex_vpc_network.custom_vpc.id

  dynamic "ingress" {
    for_each = ["80", "443", "22", "5432", "2380", "2379", "8008", "6432"]
    content {
      protocol       = "TCP"
      v4_cidr_blocks = ["0.0.0.0/0"]
      port           = ingress.value
    }
  }

  egress {
    protocol       = "ANY"
    description    = "Outcoming traf"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = -1
  }
}
resource "yandex_vpc_gateway" "custom_nat_gateway" {
  name = "custom-nat-gateway"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "custom_nat_route_table" {
  name       = "custom_nat_route_table"
  network_id = yandex_vpc_network.custom_vpc.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.custom_nat_gateway.id
  }
}

resource "yandex_alb_load_balancer" "custom_balancer" {
  name = "my-load-balancer"

  network_id = yandex_vpc_network.custom_vpc.id

  allocation_policy {
    location {
      zone_id   = "ru-central1-c"
      subnet_id = yandex_vpc_subnet.custom_subnet.id
    }
  }

  listener {
    name = "my-listener"
    endpoint {
      address {
        external_ipv4_address {
          address = yandex_vpc_address.custom_addr.external_ipv4_address[0].address
        }
      }
      ports = [80]
    }
    stream {
      handler {
        backend_group_id = yandex_alb_backend_group.custom_backend_group.id
      }
    }
  }
}


resource "yandex_alb_backend_group" "custom_backend_group" {
  name = "my-backend-group"

  stream_backend {
    name             = "test-stream-backend"
    weight           = 1
    port             = 80
    target_group_ids = ["${yandex_alb_target_group.custom_target_group.id}"]
    load_balancing_config {
      panic_threshold = 0
    }
    healthcheck {
      timeout  = "1s"
      interval = "1s"
      stream_healthcheck {
        send = ""
      }
    }
  }
}


resource "yandex_alb_target_group" "custom_target_group" {
  name = "my-target-group"

  target {
    subnet_id  = yandex_vpc_subnet.custom_subnet.id
    ip_address = yandex_compute_instance.nginx[0].network_interface.0.ip_address
  }

  target {
    subnet_id  = yandex_vpc_subnet.custom_subnet.id
    ip_address = yandex_compute_instance.nginx[1].network_interface.0.ip_address
  }
}

//////// CUSTOM GROUP FOR DATABASE ROUTING //////

/////////////////////////////////////////////////////////

resource "terraform_data" "run_ansible" {
  depends_on = [yandex_compute_instance.database, yandex_compute_instance.nginx, yandex_compute_instance.backend, yandex_compute_instance.admin]
  provisioner "local-exec" {
    command = <<EOF
    ansible-playbook -u ubuntu -i hosts.ini --private-key ${var.private_key_path} web-service.yml --extra-var "public_ip=${yandex_vpc_address.custom_addr.external_ipv4_address[0].address} private_key=${var.private_key_path}"
    rm -rf /tmp/fetched
    ansible-playbook -i postgresql_cluster/inventory postgresql_cluster/deploy_pgcluster.yml
    EOF
  }
}
