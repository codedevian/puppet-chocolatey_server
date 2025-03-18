# chocolatey_server - Host your own Chocolatey package repository
#
# @author Rob Reynolds and puppet-chocolatey_server contributors
#
# @example Default - install the server
#   include chocolatey_server
#
# @example Use a different port
#   class {'chocolatey_server':
#     port => '8080',
#   }
#
# @example Use an internal source for installing the `chocolatey.server` package
#   class {'chocolatey_server':
#     server_package_source => 'http://someinternal/nuget/odatafeed',
#   }
#
# @example Use a local file source for the `chocolatey.server` package
#   class {'chocolatey_server':
#     server_package_source => 'c:/folder/containing/packages',
#   }
#
# @param [String] hostname The hostname is blank by default so that IIS
#   binds to all hostnames. Defaults to blank
# @param [String] port The port for the server website. Defaults to '80'.
# @param [String] protocol The protocal for IIS to use. Defaults to 'http'.
# @param [String] tls_cert_thumbprint The thumbprint of the certificate. 
#   Defaults to undefined.
# @param [String] tls_cert_storename The location in the certificate store
#   where the certificate is stored. Defaults to 'My'.
# @param [String] server_package_source The chocolatey source that contains
#   the `chocolatey.server` package. Defaults to
#   'https://chocolatey.org/api/v2/'.
# @param [String] server_install_location The location to that the chocolatey
#   server will be installed.  This is can be used if you are controlling
#   the location that chocolatey packages are being installed via some other
#   means. e.g. environment variable ChocolateyBinRoot.  Defaults to
#   'C:\tools\chocolatey.server'
class chocolatey_server (
  $hostname                = $::chocolatey_server::params::service_hostname,
  $port                    = $::chocolatey_server::params::service_port,
  $protocol                = $::chocolatey_server::params::service_protocol,
  $tls_cert_thumbprint     = $::chocolatey_server::params::service_tls_cert_thumbprint,
  $tls_cert_storename      = $::chocolatey_server::params::service_tls_cert_storename,
  $server_package_source   = $::chocolatey_server::params::server_package_source,
  $server_install_location = $::chocolatey_server::params::server_install_location,
) inherits ::chocolatey_server::params {
  require chocolatey

  $_chocolatey_server_app_pool_name            = 'chocolateyserver'
  $_chocolatey_server_app_hostname             = $hostname
  $_chocolatey_server_app_port                 = $port
  $_chocolatey_server_app_protocol             = $protocol
  $_chocolatey_server_app_tls_cert_thumbprint  = $tls_cert_thumbprint
  $_chocolatey_server_app_tls_cert_storename   = $tls_cert_storename
  $_server_package_url                         = $server_package_source
  $_chocolatey_server_location                 = $server_install_location
  $_is_windows_2008 = $::kernelmajversion ? {
    '6.1'   => true,
    default => false
  }
  $_install_management_tools = $_is_windows_2008 ? {
    true    => false,
    default => true
  }
  $_web_asp_net = $_is_windows_2008 ? {
    true    => 'Web-Asp-Net',
    default => 'Web-Asp-Net45'
  }

  # package install
  package {'chocolatey.server':
    ensure   => installed,
    provider => chocolatey,
    source   => $_server_package_url,
  }

  # add windows features
  iis_feature { 'Web-WebServer':
    ensure                   => present,
    include_management_tools => $_install_management_tools,
  }
  -> iis_feature { $_web_asp_net:
    ensure => present,
  }
  -> iis_feature { 'Web-AppInit':
    ensure => present,
  }

  # remove default web site
  -> iis_site {'Default Web Site':
    ensure          => absent,
    applicationpool => 'DefaultAppPool',
    require         => Iis_feature['Web-WebServer'],
  }

  # iis bindings
  if ($_chocolatey_server_app_protocol == 'https') {
    $bindings = [
      {
        'bindinginformation' => "*:${_chocolatey_server_app_port}:${_chocolatey_server_app_hostname}",
        'protocol'           => $_chocolatey_server_app_protocol,
        'certificatehash'     => $_chocolatey_server_app_tls_cert_thumbprint,
        'certificatestorename' => $_chocolatey_server_app_tls_cert_storename,
        'sslflags' => 1
      },
    ]
  } else {
    $bindings = [
      {
        'bindinginformation' => "*:${_chocolatey_server_app_port}:${_chocolatey_server_app_hostname}",
        'protocol'           => $_chocolatey_server_app_protocol,
      },
    ]
  }

  # application in iis
  -> iis_application_pool { $_chocolatey_server_app_pool_name:
    ensure                    => 'present',
    state                     => 'started',
    enable32_bit_app_on_win64 => true,
    managed_runtime_version   => 'v4.0',
    start_mode                => 'AlwaysRunning',
    idle_timeout              => '00:00:00',
    restart_time_limit        => '00:00:00',
  }
  -> iis_site {'chocolateyserver':
    ensure          => 'started',
    physicalpath    => $_chocolatey_server_location,
    applicationpool => $_chocolatey_server_app_pool_name,
    preloadenabled  => true,
    bindings        => $bindings,
    require         => Package['chocolatey.server'],
  }

  # lock down web directory
  -> acl { $_chocolatey_server_location:
    purge                      => true,
    inherit_parent_permissions => false,
    permissions                => [
      { identity => 'Administrators', rights => ['full'] },
      { identity => 'IIS_IUSRS', rights => ['read'] },
      { identity => 'IUSR', rights => ['read'] },
      { identity => "IIS APPPOOL\\${_chocolatey_server_app_pool_name}", rights => ['read'] }
    ],
    require                    => Package['chocolatey.server'],
  }
  -> acl { "${_chocolatey_server_location}/App_Data":
    permissions => [
      { identity => "IIS APPPOOL\\${_chocolatey_server_app_pool_name}", rights => ['modify'] },
      { identity => 'IIS_IUSRS', rights => ['modify'] }
    ],
    require     => Package['chocolatey.server'],
  }
  # technically you may only need IIS_IUSRS but I have not tested this yet.
}
