//
//  main.swift
//

import PerfectHTTP
import PerfectHTTPServer
import PerfectCRUD
import PerfectThread
import PerfectCrypto
import PerfectRedis

_ = PerfectCrypto.isInitialized

CRUDLogging.queryLogDestinations = []

#if os(Linux)
	var port = 80
#else
	var port = 8080
#endif
let authServerPubKey = try PEMKey(pemPath: "./config/jwtRS256.key.pub")

do {
	let rds = biqDatabaseInfo
	try rds.initBiqDatabase()
} catch {
	let msg = "Unable to initialize qBiq database. This is fatal error. \(error.localizedDescription)"
	CRUDLogging.log(.error, msg)
	CRUDLogging.flush()
	Threading.sleep(seconds: 1.0)
	fatalError(msg)
}

try configureNotifications()

let info = biqRedisInfo
let redisAddr = RedisClientIdentifier(withHost: info.hostName, port: info.hostPort)
let workGroup = RedisWorkGroup(redisAddr)
workGroup.add(worker: TheWatcher())
workGroup.add(worker: ObsPoller())
workGroup.add(worker: NotePoller())

let routes = mainRoutes()
try HTTPServer.launch(name: "api.ubiqweus.com", port: port, routes: routes)