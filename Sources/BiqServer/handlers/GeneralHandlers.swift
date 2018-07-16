//
//  Handlers.swift
//

import Foundation
import PerfectHTTP
import PerfectCRUD
import SwiftCodables
import PerfectCrypto
import SAuthCodables

struct AuthorizedAccount {
	let token: String
	let id: UUID
}

typealias RequestSession = (request: HTTPRequest, session: AuthorizedAccount)

struct Handlers {
	static func healthCheck(request: HTTPRequest) throws -> HealthCheckResponse {
		return HealthCheckResponse(health: "OK")
	}
	static func authCheck(request: HTTPRequest) throws -> RequestSession {
		guard let bearer = request.header(.authorization), !bearer.isEmpty else {
			throw HTTPResponseError(status: .unauthorized, description: "No authorization header provided.")
		}
		let prefix = "Bearer "
		let token: String
		if bearer.hasPrefix(prefix) {
			token = String(bearer[bearer.index(bearer.startIndex, offsetBy: prefix.count)...])
		} else {
			token = bearer
		}
		do {
			if let jwtVer = JWTVerifier(token) {
				try jwtVer.verify(algo: .rs256, key: authServerPubKey)
				let payload = try jwtVer.decode(as: TokenClaim.self)
				if let accountId = payload.accountId {
					return (request, AuthorizedAccount(token: token, id: accountId))
				}
			}
		} catch {}
		throw HTTPResponseError(status: .unauthorized, description: "Invalid authorization header provided.")
	}
}





