require "base64"
require 'open3'
require 'json'

$possible_switch_types = %w[Private Internal External]

def run(cmd)
  # puts "Cmd: '#{cmd}'"
  output = `powershell.exe -encodedCommand #{Base64.strict_encode64(cmd.encode('utf-16le'))}`
  # puts "Output: #{output}"
  output
end

def list_switches
  output = run("Get-VMSwitch | SELECT Name, SwitchType, NetAdapterInterfaceDescription | ConvertTo-Json")
  switches = JSON.parse(output)
  switches.map do |switch|
    {
      "name" => (switch["Name"] || "").strip,
      "type" => ($possible_switch_types[switch["SwitchType"]] || "").strip,
      "net_adapter_interface" => (switch["NetAdapterInterfaceDescription"] || "").strip
    }
  end
end

def create_switch(name, type, net_adapter_interface="")
  if $possible_switch_types.include?(type)
    cmd = "New-VMSwitch -Name '#{name}'"
    if type == "External"
      cmd = cmd + " -NetAdapterInterfaceDescription '#{net_adapter_interface}'"
    else
      cmd = cmd + " -SwitchType #{type}"
    end
    run(cmd)
  else
    raise "Error: Unauthorized Switch Type"
  end
end

def get_disks(vm_name)
  output = run("Get-VMHardDiskDrive -VMName #{vm_name} | SELECT ControllerType, Path | ConvertTo-Json")
  disks = JSON.parse(output)
  unless disks.kind_of?(Array)
    disks = [disks]
  end
  disks.map do |adapter|
    {
      "path" => (adapter["Path"] || "").strip,
      "controller_type" => adapter["ControllerType"]
    }
  end
end

def create_vhd(disk_path, gb_size)
  run("New-VHD -Path '#{disk_path}' -SizeBytes #{gb_size}gb -Dynamic")
end

def add_vhd(vm_name, disk_path, controller_type = "SCSI", controller_number = 0)
  run("Add-VMHardDiskDrive -VMName #{vm_name} -Path '#{disk_path}' -ControllerType #{controller_type} -ControllerNumber #{controller_number}")
end

def list_physical_net_adapter
  output = run("Get-NetAdapter -Name * -Physical | SELECT Name, InterfaceDescription, Status | ConvertTo-Json")
  adapters = begin
               JSON.parse(output)
             rescue StandardError
               []
             end
  unless adapters.kind_of?(Array)
    adapters = [adapters]
  end
  adapters.map do |adapter|
    {
      "name" => (adapter["Name"] || "").strip,
      "description" => (adapter["InterfaceDescription"] || "").strip,
      "status" => (adapter["Status"] || "").strip
    }
  end
end

def list_net_adapter(vm_name)
  output = run("Get-VMNetworkAdapter -VMName #{vm_name} | SELECT SwitchName, IPAddresses | ConvertTo-Json")
  adapters = begin
               JSON.parse(output)
             rescue StandardError
               []
             end
  unless adapters.kind_of?(Array)
    adapters = [adapters]
  end
  adapters.map do |adapter|
    {
      "switch_name" => (adapter["SwitchName"] || "").strip,
      "ip_addresses" => adapter["IPAddresses"] || []
    }
  end
end

def add_net_adapter(vm_name, switch_name, mac_address)
  run("Add-VMNetworkAdapter -VMName '#{vm_name}' -SwitchName '#{switch_name}' -StaticMacAddress #{mac_address}")
end

def switch_index(name, type, net_adapter_interface = "")
  if $possible_switch_types.include?(type)
    switches = list_switches
    switches.find_index do |switch|
      switch["name"] == name && switch["type"] == type && switch["net_adapter_interface"] == net_adapter_interface
    end
  else
    raise "Error: Unauthorized Switch Type"
  end
end

def switch_adapter_index(vm_name, switch_name)
  adapters = list_net_adapter(vm_name)
  adapters.find_index do |adapter|
    adapter["switch_name"] == switch_name
  end
end