output "lb_ip" {
  value = yandex_vpc_address.custom_addr.external_ipv4_address[0].address
}

output "admin_ip" {
  value = yandex_compute_instance.admin.network_interface.0.nat_ip_address
}
