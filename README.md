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

### Authentication

All endpoints, with the exception of the "healthcheck", require that the user be authenticated with the qBiq auth server. All requests should include the authentication token returned by the auth server as an HTTP bearer token.

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
<tr><td colspan=4>Registers the device as belonging to the current user. It is *not* an error if the device is already registered to the current user or any other user. In any case the device's `ownerId` property will indicate if the registration was successful. If the device is registered to someone else this property will be nil. An error will be generated if the specified device id is not valid.</td>
</tr>
<tr><td>/v1/device/unregister</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI.html#/s:13SwiftCodables9DeviceAPIO15RegisterRequesta">RegisterRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/device/limits	</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/UpdateLimitsRequest.html">UpdateLimitsRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI.html#/s:13SwiftCodables9DeviceAPIO0C14LimitsResponsea">DeviceLimitsResponse</a></td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/device/update</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/UpdateRequest.html">UpdateRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/device/share</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ShareRequest.html">ShareRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDevice.html">BiqDevice</a></td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/device/share/token</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ShareTokenRequest.html">ShareTokenRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ShareTokenResponse.html">ShareTokenResponse</a></td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/device/unshare</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ShareRequest.html">ShareRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/device/obs/delete</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/GenericDeviceRequest.html">GenericDeviceRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/device/limits</td>
<td>GET</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI.html#/s:13SwiftCodables9DeviceAPIO13LimitsRequesta">LimitsRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI.html#/s:13SwiftCodables9DeviceAPIO0C14LimitsResponsea">DeviceLimitsResponse</a></td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/device/list</td>
<td>GET</td>
<td>-</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ListDevicesResponseItem.html">[ListDevicesResponseItem]</a></td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/device/info</td>
<td>GET</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/GenericDeviceRequest.html">GenericDeviceRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDevice.html">BiqDevice</a></td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/device/obs</td>
<td>GET</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ObsRequest.html">ObsRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/ObsDatabase/BiqObservation.html">[BiqObservation]</a></td>
</tr>
<tr><td colspan=4></td>
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
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/group/device/add</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/AddDeviceRequest.html">AddDeviceRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/group/device/remove</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/AddDeviceRequest.html">AddDeviceRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/group/delete</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/DeleteRequest.html">DeleteRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/group/update</td>
<td>POST</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/UpdateRequest.html">UpdateRequest</a></td>
<td>Empty</td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/group/device/list</td>
<td>GET</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/ListDevicesRequest.html">ListDevicesRequest</a></td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDevice.html">[BiqDevice]</a></td>
</tr>
<tr><td colspan=4></td>
</tr>
<tr><td>/v1/group/list</td>
<td>GET</td>
<td>-</td>
<td><a href="https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDeviceGroup.html">[BiqDeviceGroup]</a></td>
</tr>
</table>

### API Errors



### Other  
GET:  
/healthcheck
