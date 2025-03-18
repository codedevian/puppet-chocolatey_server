# chocolatey_server::params
#
# This class is meant to be called from chocolatey_server.
# It sets variables according to platform.
class chocolatey_server::params {
  case $::osfamily {
    'windows': {
      $service_hostname                = ''
      $service_port                    = '80'
      $service_protocol                = 'http'
      $service_tls_cert_thumbprint     = undef
      $service_tls_cert_storename      = 'My'
      $server_package_source           = 'https://chocolatey.org/api/v2/'
      $server_install_location         = 'C:\tools\chocolatey.server'
    }
    default: {
      fail("${::operatingsystem} not supported")
    }
  }
}
