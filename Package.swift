// swift-tools-version:4.0
// Generated automatically by Perfect Assistant
// Date: 2018-04-27 13:54:57 +0000
import PackageDescription

let package = Package(
	name: "BiqServer",
	products: [
		.executable(name: "biqserver", targets: ["BiqServer"])
	],
	dependencies: [
		.package(url: "https://github.com/PerfectlySoft/Perfect-HTTPServer.git", from: "3.0.0"),
		.package(url: "https://github.com/PerfectlySoft/Perfect-CloudFormation.git", from: "0.0.0"),
		.package(url: "https://github.com/PerfectlySoft/Perfect-PostgreSQL.git", from: "3.1.0"),
		.package(url: "https://github.com/PerfectlySoft/Perfect-CRUD.git", from: "1.0.0"),
		.package(url: "https://github.com/PerfectlySoft/Perfect-Notifications.git", from: "3.0.0"),
		.package(url: "https://github.com/PerfectlySoft/Perfect-Redis.git", from: "3.2.0"),
		.package(url: "https://github.com/kjessup/BiqSwiftCodables.git", .branch("master")),
		.package(url: "https://github.com/kjessup/SAuthCodables.git", .branch("master")),
	],
	targets: [
		.target(name: "BiqServer", dependencies: [
			"PerfectHTTPServer",
			"PerfectPostgreSQL",
			"PerfectCRUD",
			"SwiftCodables",
			"PerfectCloudFormation",
			"PerfectRedis",
			"PerfectNotifications",
			"SAuthCodables"])
	]
)
