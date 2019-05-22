//
//  RecipeHandlers.swift
//  BiqServer
//
//  Created by Rocky Wei on 2019-05-07.
//

import Foundation
import PerfectHTTP
import PerfectCRUD
import SwiftCodables
import SAuthCodables
import PerfectLib
import PerfectPostgreSQL
import Foundation
import PerfectPostgreSQL
import PerfectCRUD

public typealias BiqRecipeResult = ProfileAPIResponse

extension BiqRecipeResult {
	init(_ value: String) {
		self.content = value
	}
}

/// qbiq recipe
extension SwiftCodables.BiqRecipe {

	/// load an instance from database by its ID
	public init?(uri i: String) {
		guard let db = BiqRecipe.pdb else { return nil }
		let table = db.table(BiqRecipe.self)
		do {
			if let record = try table.where(\BiqRecipe.uri == i).first() {
				self = BiqRecipe(title: record.title, author: record.author, description: record.description)
			} else {
				return nil
			}
		} catch {
			return nil
		}
	}
	
	/// inner database handler
	private static var pdb: Database<PostgresDatabaseConfiguration>? = nil
	
	/// MUST call this function first to build all tables associated.
	/// - parameter config: configuration
	/// - returns: true for success
	public static func prepare(config: PostgresDatabaseConfiguration) -> Bool {
		pdb = Database(configuration: config)
		guard let db = pdb else { return false }
		do {
			try db.create(BiqRecipeTag.self, policy: [.reconcileTable, .shallow]).index(unique: true, \BiqRecipeTag.uri, \BiqRecipeTag.tag)
			try db.create(BiqRecipeMedia.self, policy: [.reconcileTable, .shallow]).index(unique: true, \BiqRecipeMedia.uri, \BiqRecipeMedia.title)
			try db.create(BiqThreshold.self, policy: [.reconcileTable, .shallow]).index(unique: true, \BiqThreshold.uri, \BiqThreshold.measurement)
			try db.create(BiqRecipe.self, primaryKey: \BiqRecipe.uri, policy: [.reconcileTable, .shallow]).index(unique: true, \BiqRecipe.title, \BiqRecipe.author)
			return true
		} catch (let err) {
			CRUDLogging.log(.error, "unable to create recipe tables because \(err)")
			return false
		}
	}
	
	/// an abstract batch operation for tags, thresholds and medium
	/// - parameter properties: a collection of either tags, threshold or medium
	/// - parameter operation: a callback function to `(table, element)`
	/// - returns: true for success. If false, none of the operation would take effect.
	private func modify<T: Codable>(properties: [T], operation: (Table<T, Database<PostgresDatabaseConfiguration>>, T) -> Bool) -> Bool {
		guard let db = BiqRecipe.pdb else { return false }
		let table = db.table(T.self)
		let ret: Int? = try? db.transaction { () -> Int in
			var total = 0
			for element in properties {
				if operation(table, element) {
					total += 1
					continue
				}
				break
			}
			return total
		}
		return ret == properties.count
	}
	
	private func readProperties<T: Codable>(filter: CRUDBooleanExpression) -> [T] {
		guard let db = BiqRecipe.pdb else { return [] }
		let table = db.table(T.self)
		do {
			let dataset = try table.where(filter).select().map { $0 }
			return dataset
		} catch (let err) {
			CRUDLogging.log(.error, "unable to read properties because \(err)")
			return []
		}
	}
	
	/// all tags associated to this recipe
	public var tags: [BiqRecipeTag] {
		return readProperties(filter: \BiqRecipeTag.uri == self.uri)
	}
	
	/// all thresholds associated to this recipe
	public var thresholds: [BiqThreshold] {
		return readProperties(filter: \BiqThreshold.uri == self.uri)
	}
	
	/// all media attachments associated to this recipe
	public var medium: [BiqRecipeMedia] {
		return readProperties(filter: \BiqRecipeMedia.uri == self.uri)
	}
	
	/// deposit this recipe to database
	/// - returns: true for success
	public func save() -> Bool {
		guard let db = BiqRecipe.pdb else { return false }
		let table = db.table(BiqRecipe.self)
		do {
			if try table.where(\BiqRecipe.uri == self.uri).count() > 0 {
				try table.update(self)
			} else {
				try table.insert(self)
			}
			return true
		} catch (let err) {
			CRUDLogging.log(.error, "unable to upsert because \(err)")
			return false
		}
	}
	
	public static func delete(uri: String) -> Bool {
		guard let db = BiqRecipe.pdb else { return false }
		do {
			let tableMedia = db.table(BiqRecipeMedia.self)
			let tableTag = db.table(BiqRecipeTag.self)
			let tableThreshold = db.table(BiqThreshold.self)
			let table = db.table(BiqRecipe.self)
			try db.transaction {
				try tableMedia.where(\BiqRecipeMedia.uri == uri).delete()
				try tableTag.where(\BiqRecipeTag.uri == uri).delete()
				try tableThreshold.where(\BiqThreshold.uri == uri).delete()
				try table.where(\BiqRecipe.uri == uri).delete()
			}
			return true
		} catch (let err) {
			CRUDLogging.log(.error, "unable to remove \(uri) because \(err)")
			return false
		}
	}

	public static func add<T: Codable>(property: T) -> Bool {
		guard let db = BiqRecipe.pdb else { return false }
		let table = db.table(T.self)
		do {
			try table.insert(property)
			return true
		} catch (let err) {
			CRUDLogging.log(.error, "unable to add property \(property) because \(err)")
			return false
		}
	}


	public static func del<T: Codable>(`type`: T.Type, condition: CRUDBooleanExpression) -> Bool {
		guard let db = BiqRecipe.pdb else { return false }
		let table = db.table(type)
		do {
			try table.where(condition).delete()
			return true
		} catch (let err) {
			CRUDLogging.log(.error, "unable to remove property because \(err)")
			return false
		}
	}

	public static let blank = CharacterSet(charactersIn: " \t\r\n")
	public static func search(_ pattern: String, limitation: Int = 100) -> [BiqRecipe] {
		guard let db = BiqRecipe.pdb else { return [] }
		
		let keys = pattern.split(separator: " ").compactMap { String($0).trimmingCharacters(in: blank ) }
		guard !keys.isEmpty else { return  [] }
		
		
		let or = " OR "
		let titleLikes = keys.map { "title LIKE '%\($0)%'" }.joined(separator: or)
		let authorLikes = keys.map { "author LIKE '%\($0)%'" }.joined(separator: or)
		let descLikes = keys.map { "description LIKE '%\($0)%'" }.joined(separator: or)
		let tagLikes = keys.map { "tag LIKE '%\($0)%'" }.joined(separator: or)
		let mediaLikes = titleLikes
		
		let limit = limitation > 0 && limitation < 101 ? limitation : 100
		let sql = """
		SELECT * FROM BiqRecipe
		WHERE \(titleLikes) OR \(authorLikes) OR \(descLikes)
		OR uri IN (SELECT DISTINCT uri FROM BiqRecipeTag WHERE \(tagLikes))
		OR uri IN (SELECT DISTINCT uri FROM BiqRecipeMedia WHERE \(mediaLikes))
		LIMIT \(limit);
		"""
		
		do {
			let result = try db.sql(sql, BiqRecipe.self)
			return result
		} catch (let err) {
			CRUDLogging.log(.error, "searching pattern \(pattern) fault: \(err)")
			return []
		}
	}
	
	public var json: String? {
		do {
			let encoded = try JSONEncoder().encode(self)
			guard let text = String(data: encoded, encoding: .utf8) else {
				CRUDLogging.log(.error, "unable to encode json into UTF8")
				return nil
			}
			return text
		} catch (let err) {
			CRUDLogging.log(.error, "unable to encode json: \(err)")
			return nil
		}
	}
}



struct RecipeHandlers {
	static func identity(session rs: RequestSession) throws -> RequestSession {
		return rs
	}
	
	static func recipeGet(session rs: RequestSession) throws -> BiqRecipe {
		guard let uri = rs.request.param(name: "uri"),
			let urlencoded = uri.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)?.lowercased(),
			let recipe = BiqRecipe(uri: urlencoded) else {
				throw HTTPResponseError(status: .badRequest, description: "Invalid recipe uri.")
		}
		return recipe
	}
	
	static func recipeSet(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let recipe = try JSONDecoder().decode(BiqRecipe.self, from: Data(postBody))
		guard recipe.save() else {
			throw HTTPResponseError(status: .badRequest, description: "Unable to save.")
		}
		return BiqRecipeResult(recipe.uri)
	}

	static func recipeDel(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let uri = rs.request.param(name: "uri"),
			BiqRecipe.delete(uri: uri) else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid uri.")
		}
		return BiqRecipeResult(uri)
	}

	static func recipeTagAdd(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let tags = try JSONDecoder().decode([BiqRecipeTag].self, from: Data(postBody))
		let total = tags.map { BiqRecipe.add(property: $0) ? 1 : 0 }.reduce(0) { $0 + $1 }
		return BiqRecipeResult("\(total)")
	}
	
	static func recipeTagRemove(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let tags = try JSONDecoder().decode([BiqRecipeTag].self, from: Data(postBody))
		let total = tags.map {
			BiqRecipe.del(type: BiqRecipeTag.self,
										condition: \BiqRecipeTag.uri == $0.uri && \BiqRecipeTag.tag == $0.tag) ? 1 : 0
		}.reduce(0) { $0 + $1 }
		return BiqRecipeResult("\(total)")
	}

	static func recipeTagGet(session rs: RequestSession) throws -> [BiqRecipeTag] {
		guard let uri = rs.request.param(name: "uri"), let recipe = BiqRecipe(uri: uri) else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid recipe uri.")
		}
		return recipe.tags
	}
	
	static func recipeMediaAdd(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let medium = try JSONDecoder().decode([BiqRecipeMedia].self, from: Data(postBody))

		let total = medium.map { BiqRecipe.add(property: $0) ? 1 : 0 }.reduce(0) { $0 + $1 }
		return BiqRecipeResult("\(total)")
	}
	
	static func recipeMediaRemove(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let medium = try JSONDecoder().decode([BiqRecipeMedia].self, from: Data(postBody))
		let total = medium.map {
			BiqRecipe.del(type: BiqRecipeMedia.self,
										condition: \BiqRecipeMedia.uri == $0.uri && \BiqRecipeMedia.title == $0.title) ? 1 : 0 }
			.reduce(0) { $0 + $1 }
		return BiqRecipeResult("\(total)")
	}

	static func recipeMediaGet(session rs: RequestSession) throws -> [BiqRecipeMedia] {
		guard let uri = rs.request.param(name: "uri"), let recipe = BiqRecipe(uri: uri) else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid recipe uri.")
		}
		return recipe.medium
	}
	
	static func recipeThresholdAdd(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let thresholds = try JSONDecoder().decode([BiqThreshold].self, from: Data(postBody))
		let total = thresholds.map { BiqRecipe.add(property: $0) ? 1 : 0 }.reduce(0) { $0 + $1 }
		return BiqRecipeResult("\(total)")
	}
	
	static func recipeThresholdRemove(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let thresholds = try JSONDecoder().decode([BiqThreshold].self, from: Data(postBody))
		let total = thresholds.map {
			BiqRecipe.del(type: BiqThreshold.self,
										condition: \BiqThreshold.uri == $0.uri && \BiqThreshold.measurement == $0.measurement) ? 1 : 0
			}.reduce(0) { $0 + $1 }
		return BiqRecipeResult("\(total)")
	}

	static func recipeThresholdGet(session rs: RequestSession) throws -> [BiqThreshold] {
		guard let uri = rs.request.param(name: "uri"), let recipe = BiqRecipe(uri: uri) else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid recipe uri.")
		}
		return recipe.thresholds
	}
	
	static func search(session rs: RequestSession) throws -> [BiqRecipe] {
		guard let pattern = rs.request.param(name: "pattern") else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid keywords")
		}
		var limit = 100
		if let limitation = rs.request.param(name: "limit") {
			limit = Int(limitation) ?? 100
		}
		return BiqRecipe.search(pattern, limitation: limit)
	}
}
