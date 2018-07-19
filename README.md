![](webroot/images/ubiqweus-logo-colour@2x.png)

# qBiqServer
## API server for qBiq based apps

This API will permit you to manage your qBiq devices.  
The functionality includes:

* Register/unregister devices
* Share/unshare devices
* Update device settings
* Assign device limits
* Retrieve device observations
* Group/ungroup devices

### Operational Notes

A qBiq device starts its life in an unowned state. A user can register a qBiq, marking it as owned by that user. A user can then  configure the qBiq and set various options. The device can be shared with other users, permitting them to see the observations (such as temperatures or movements) collected by the device. Multiple devices can be placed in logical groups permitting expanded organization of a user's devices. A device may be unregistered and its observation data may be expunged.

All of these tasks are accomplished through the API endpoints provided by this server and documented below.

### Authentication

All endpoints, with the exception of the "healthcheck", require that the user be authenticated with the qBiq auth server. All requests should include the authentication token returned by the auth server as an HTTP "Authorization" header bearer token.

```
...
Authorization: Bearer eyJhbGciOiJSU...this is an example token
...
```

All requests must be made over HTTPS. Some responses are noted as "Empty". This indicates an empty JSON object "{}".

### Device API

<table>
<tr><th>Endpoint URI</th><th>Method</th><th>Input</th><th>Output</th></tr>
<tr>
<td>/v1/device/register</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI.html#/s:13SwiftCodables9DeviceAPIO15RegisterRequesta">RegisterRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDevice.html">BiqDevice</a></td>
</tr>
<tr><td colspan=4>Registers the device as belonging to the current user. It is not an error if the device is already registered to the current user or any other user. In any case the device's `ownerId` property will indicate if the registration was successful. If the device is registered to someone else this property will be nil. An error will be generated if the specified device id is not valid.</td>
</tr>
<tr><td>/v1/device/unregister</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI.html#/s:13SwiftCodables9DeviceAPIO15RegisterRequesta">RegisterRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4>Unregister the device, marking it as un-owned. The device can then be registered again by any user. An error will be generated if the specified device id is not valid or if the device is not owned by the current user. When  a device is unregistered it is removed from all shares for all users, from all groups for all users, and all limits are removed. However, all observation data is not removed. Use the `/v1/device/obs/delete` endpoint to delete observation data.</td>
</tr>
<tr><td>/v1/device/limits</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/UpdateLimitsRequest.html">UpdateLimitsRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI.html#/s:13SwiftCodables9DeviceAPIO0C14LimitsResponsea">DeviceLimitsResponse</a></td>
</tr>
<tr><td colspan=4>Update the user's personal settings (henceforth referred to as limits) for this device. The various types of limits are defined as <a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDeviceLimitType.html">BiqDeviceLimitType</a>. An error will be generated if the specified device id is not valid or if the device is not shared to or owned by the current user. Limits such as `interval`, `reportFormat`, and `reportBufferCapacity` have no affect if the user is not the device's owner. Additionally, while limits can be set by any user, only the owner can set limits which get pushed to the device to control its behaviour. For example, any user can set a device's personal display colour, but only the owner's colour choice will propagate to the device to change its LEDs.</td>
</tr>
<tr><td>/v1/device/update</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/UpdateRequest.html">UpdateRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4>Update a device's name and/or flags. An error will be generated if the specified device id is not valid or if the device is not owned by the current user. Providing nil for the name will not modify its stored value. Currently, only the `locked` device flag can be set/cleared.</td>
</tr>
<tr><td>/v1/device/share</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ShareRequest.html">ShareRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDevice.html">BiqDevice</a></td>
</tr>
<tr><td colspan=4>Attempt to share the device to the current user. If the device is locked a valid share token is required. If the current user is the device's owner or the device has already been shared with the current user it is considered a no-op and no error is generated. An error is generated if the device id is not valid or if the device is locked and no valid share token was provided.</td>
</tr>
<tr><td>/v1/device/share/token</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ShareTokenRequest.html">ShareTokenRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ShareTokenResponse.html">ShareTokenResponse</a></td>
</tr>
<tr><td colspan=4>Generate and return a new share token which can be used once by another user to share the device. This is required to share a locked device. Share tokens expire after 15 days. An error is generated if the user is not the device's owner.</td>
</tr>
<tr><td>/v1/device/unshare</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ShareRequest.html">ShareRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4>Unshare a device which had been previously shared with the user. An error will be generated if the device has not been shared with the user or if the user is the device's owner. The device will be removed from the user's groups and all personal limits on the device will be removed.</td>
</tr>
<tr><td>/v1/device/obs/delete</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/GenericDeviceRequest.html">GenericDeviceRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4>Delete all observation data for the device. An error will be generated if the user is not the device's owner.</td>
</tr>
<tr><td>/v1/device/limits</td>
<td>GET</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI.html#/s:13SwiftCodables9DeviceAPIO13LimitsRequesta">LimitsRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI.html#/s:13SwiftCodables9DeviceAPIO0C14LimitsResponsea">DeviceLimitsResponse</a></td>
</tr>
<tr><td colspan=4>Return all limits set by the user for this device. An error will be generated if the device id is not valid or if the device is not owned by or has not been shared with the user.</td>
</tr>
<tr><td>/v1/device/list</td>
<td>GET</td>
<td>-</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ListDevicesResponseItem.html">[ListDevicesResponseItem]</a></td>
</tr>
<tr><td colspan=4>List all devices owned by or shared with the user.</td>
</tr>
<tr><td>/v1/device/info</td>
<td>GET</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/GenericDeviceRequest.html">GenericDeviceRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDevice.html">BiqDevice</a></td>
</tr>
<tr><td colspan=4>Retrieve basic information about a device. This includes devices which are owned by others or those which have not yet been registered.</td>
</tr>
<tr><td>/v1/device/obs</td>
<td>GET</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ObsRequest.html">ObsRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/ObsDatabase/BiqObservation.html">[BiqObservation]</a></td>
</tr>
<tr><td colspan=4>Retrieve observation data on a device. An error will be generated if the device id is not valid or if the device is not owned by or has not been shared with the user. Various intervals of data can be formulated and returned. These are enumerated as <a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ObsRequest/Interval.html">ObsRequest.Interval</a>.</td>
</tr>
</table>

### Group API  
<table>
<tr><th>Endpoint URI</th><th>Method</th><th>Input</th><th>Output</th></tr>
<tr><td>/v1/group/create</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/CreateRequest.html">CreateRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDeviceGroup.html">BiqDeviceGroup</a></td>
</tr>
<tr><td colspan=4>Create a new empty device group with the given name.</td>
</tr>
<tr><td>/v1/group/device/add</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/AddDeviceRequest.html">AddDeviceRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4>Add a device to a group. An error will be generated if the device or group id is invalid or if the device is not owned by or has not been shared with the user. A device may belong to multiple groups.</td>
</tr>
<tr><td>/v1/group/device/remove</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/AddDeviceRequest.html">AddDeviceRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4>Remove a device from a group. An error will be generated if the device or group id is invalid. If the device is not in the group or if the user does not have access to the device it is considered a no-op and no error is generated.</td>
</tr>
<tr><td>/v1/group/delete</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/DeleteRequest.html">DeleteRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4>Delete the indicated group. Attempting to delete a group which does not exist or which does not belong to the user is considered a no-op and no error is generated.</td>
</tr>
<tr><td>/v1/group/update</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/UpdateRequest.html">UpdateRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4>Update a group's name. Attempting to update a group which does not exist or which does not belong to the user is considered a no-op and no error is generated.</td>
</tr>
<tr><td>/v1/group/device/list</td>
<td>GET</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/ListDevicesRequest.html">ListDevicesRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDevice.html">[BiqDevice]</a></td>
</tr>
<tr><td colspan=4>List the devices in the indicated group. An error is generated if the group does not exist or if it does not belong to the user.</td>
</tr>
<tr><td>/v1/group/list</td>
<td>GET</td>
<td>-</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDeviceGroup.html">[BiqDeviceGroup]</a></td>
</tr>
<tr><td colspan=4>List the groups the user has created.</td>
</tr>
</table>

### Health Check

The endpoint `/healthcheck` will return 200 OK.

### API Errors

API usage errors will generate a "400 Bad Request" HTTP response.
Internal errors related to things such as database connectivity will generate a "500 Internal Server Error" HTTP response. In either case the response body will be a JSON encoded `HTTPResponseError` struct containing `status` and `description` properties. The status will mirror the HTTP response code/status and the description will provide further information on the cause.
