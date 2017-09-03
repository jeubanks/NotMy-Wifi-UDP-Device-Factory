/*
 * Plugin for Belkin WeMo
 * Copyright (C) 2009-2011 Deborah Pickett

 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

/**********
 *
 * Configuration tab
 *
 **********/
/*
 * Replaces prototype string.escapeHTML
 */

ECO_SID = "urn:micasaverde-com:serviceId:ECO_Switch1";

function EscapeHtml(string)
{
	return string.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

function configuration(device)
{
	var html = '';
	html += '<p id="eco_refresh" style="display:none; font-weight: bold; text-align: center;">Wait for the LuaUPnP engine to reload, and refresh your browser!</p>';

	// List known child devices, with option to delete them.
	var childDevices = JSON.parse(get_device_state(device, ECO_SID, "CONFIGURED_DEVICES", 1));

	var actualChildDevices = 0;
	var actualFoundDevices = 0;
	var childHtml = '';
	var foundHtml = '';
	var dynamicCount = 0;
	childHtml += '<div style="border: black 1px solid; padding: 5px; margin: 5px;">';
	childHtml += '<div style="font-weight: bold; text-align: center;">Configured ECO_Switch devices</div>';
	childHtml += '<table width="100%"><thead><th>Name&#xA0;</th><th>ID</th><th>IP&#xA0;Address</th><th>Action</th></thead>';
	var i;
	for (var devIdx in childDevices)
	{
		// Find the child in the device list (requires exhaustive search).
		var childName = childDevices[devIdx].Name;
		var childID = childDevices[devIdx].ID;
		var childIP = childDevices[devIdx].IP;
		childHtml += '<tr>';
		childHtml += '<td>' + EscapeHtml(childName) + '</td>';
		childHtml += '<td>' + EscapeHtml(childID) + '</td>';
		childHtml += '<td>' + EscapeHtml(childIP) + '</td>';
		childHtml += '<td><input type="button" value="Remove" onClick="configurationRemoveChildDevice(' + device + ',' + devIdx + ',this)"/></td>';
		childHtml += '</tr>';
		actualChildDevices++;
	}
	childHtml += '</table>';
	childHtml += '</div>';
	if (actualChildDevices) { html += childHtml; }

	// display discovered devices on the network. 
	foundHtml += '<div style="border: black 1px solid; padding: 5px; margin: 5px;">';

	// List unknown devices as candidates to add.
	var unknownDevices = JSON.parse(get_device_state(device, ECO_SID, "DISCOVERED_DEVICES", 1));
	foundHtml += '<div style="font-weight: bold; text-align: center;">Discovered ECO_Switch devices</div>';
	foundHtml += '<table id="wemo_scanResults" width="100%"><thead><th>Name&#xA0;</th><th>ID</th><th>IP&#xA0;Address</th><th>Action</th></thead>';
	var i;
	for (var devIdx in unknownDevices)
	{
		var unknownDeviceName = unknownDevices[devIdx].Name;
		var unknownDeviceID = unknownDevices[devIdx].ID;
		var unknownDeviceIP = unknownDevices[devIdx].IP;
		var dConfigured = false;
		for (var devI in childDevices)
		{
			if ((childDevices[devI].Name == unknownDeviceName) && (childDevices[devI].ID == unknownDeviceID) && (childDevices[devI].IP == unknownDeviceIP)) {
				dConfigured = true;
				break;
			}
		}
		if (dConfigured) {
			continue;
		}
		foundHtml += '<tr>';
		foundHtml += '<td>' + EscapeHtml(unknownDeviceName) + '</td>';
		foundHtml += '<td>' + EscapeHtml(unknownDeviceID) + '</td>';
		foundHtml += '<td>' + EscapeHtml(unknownDeviceIP) + '</td>';
		foundHtml += '<td>';
		foundHtml += '<input type="button" value="Add" onClick="configurationAddFoundDevice('
		 + device + ',' + devIdx + ',this)"/></td>';
		foundHtml += '</tr>';
		actualFoundDevices++;
	}
	foundHtml += '</table>';

	html += '</div>';
	if (actualFoundDevices) { html += foundHtml; }


	set_panel_html(html);
}

// Remove an existing device.
function configurationRemoveChildDevice(device, index, button)
{
	var btn = jQuery(button);
	btn.attr('disabled', 'disabled')
	jQuery(':button').attr('disabled', 'disabled');
//	$(':button').prop('disabled', true);
	
	var configuredDevices = JSON.parse(get_device_state(device, ECO_SID, "CONFIGURED_DEVICES", 1));
	var DeviceToRemove = configuredDevices[index];

	var removeUrl = '/port_3480/data_request?id=lu_action&action=RemoveConfiguredDevice&DeviceNum='+device+'&serviceId='+ECO_SID+'&DeviceData='+JSON.stringify(DeviceToRemove);
//alert("removeUrl:"+removeUrl);
	jQuery.get(removeUrl);

	btn.val("Removing");
	jQuery('#eco_refresh').show();
}

// Add a found device.
function configurationAddFoundDevice(device, index, button)
{
	var btn = jQuery(button);
	btn.parent('input').attr('disabled', 'disabled');
//	$(':button').prop('disabled', true); 
	jQuery(':button').attr('disabled', 'disabled'); 

	var unknownDevices = JSON.parse(get_device_state(device, ECO_SID, "DISCOVERED_DEVICES", 1));
	var DeviceToAdd = unknownDevices[index];

	var addUrl = '/port_3480/data_request?id=lu_action&action=AddDiscoveredDevice&DeviceNum='+device+'&serviceId='+ECO_SID+'&DeviceData='+JSON.stringify(DeviceToAdd);
//alert("addUrl:"+addUrl);
	jQuery.get(addUrl);

	btn.val("Adding");
	jQuery('#eco_refresh').show();
}

