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

|Endpoint URI	|Method	|Input	|Output|Description|
|--------------|-------|-------|------|-----------|
|/v1/device/register|POST|[RegisterRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI.html#/s:13SwiftCodables9DeviceAPIO15RegisterRequesta)|[BiqDevice](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDevice.html)|X|
||||Registers the device as belonging to the current user. It is *not* an error if the device is already registered to the current user or any other user. In any case the device's `ownerId` property will indicate if the registration was successful. If the device is registered to someone else this property will be nil. An error will be generated if the specified device does not exist.|
|/v1/device/unregister|POST|[RegisterRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI.html#/s:13SwiftCodables9DeviceAPIO15RegisterRequesta)|Empty|Words|
|/v1/device/limits	|POST|[UpdateLimitsRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/UpdateLimitsRequest.html)|[DeviceLimitsResponse](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI.html#/s:13SwiftCodables9DeviceAPIO0C14LimitsResponsea)|Words|
|/v1/device/update|POST|[UpdateRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/UpdateRequest.html)|Empty|Words|
|/v1/device/share|POST|[ShareRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ShareRequest.html)|[BiqDevice](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDevice.html)|Words|
|/v1/device/share/token|POST|[ShareTokenRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ShareTokenRequest.html)|[ShareTokenResponse](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ShareTokenResponse.html)|Words|
|/v1/device/unshare|POST|[ShareRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ShareRequest.html)|Empty|Words|
|/v1/device/obs/delete|POST|[GenericDeviceRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/GenericDeviceRequest.html)|Empty|Words|
|/v1/device/limits|GET|[LimitsRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI.html#/s:13SwiftCodables9DeviceAPIO13LimitsRequesta)|[DeviceLimitsResponse](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI.html#/s:13SwiftCodables9DeviceAPIO0C14LimitsResponsea)|Words|
|/v1/device/list|GET|-|[[ListDevicesResponseItem]](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ListDevicesResponseItem.html)|Words|
|/v1/device/info|GET|[GenericDeviceRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/GenericDeviceRequest.html)|[BiqDevice](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDevice.html)|Words|
|/v1/device/obs|GET|[ObsRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/DeviceAPI/ObsRequest.html)|[[BiqObservation]](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/ObsDatabase/BiqObservation.html)|Words|

### Group API  
|Endpoint URI	|Method	|Input	|Output|Description|
|--------------|-------|-------|------|-----------|
|/v1/group/create|POST|[CreateRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/CreateRequest.html)|[BiqDeviceGroup](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDeviceGroup.html)|Words|
|/v1/group/device/add|POST|[AddDeviceRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/AddDeviceRequest.html)|Empty|Words|
|/v1/group/device/remove|POST|[AddDeviceRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/AddDeviceRequest.html)|Empty|Words|
|/v1/group/delete|POST|[DeleteRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/DeleteRequest.html)|Empty|Words|
|/v1/group/update|POST|[UpdateRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/UpdateRequest.html)|Empty|Words|
|/v1/group/device/list|GET|[ListDevicesRequest](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Enums/GroupAPI/ListDevicesRequest.html)|[[BiqDevice]](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDevice.html)|Words|
|/v1/group/list|GET|-|[[BiqDeviceGroup]](https://htmlpreview.github.io/?https://raw.githubusercontent.com/ubiqweus/qBiqSwiftCodables/master/docs/Structs/BiqDeviceGroup.html)|Words|

### API Errors



### Other  
GET:  
/healthcheck
