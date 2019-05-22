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


public struct BiqRecipeResult: Codable {
	public let value: Int
	public init(_ value: Int) {
		self.value = value
	}
}

/// qbiq recipe
extension BiqRecipe: Comparable {
	public static func == (lhs: BiqRecipe, rhs: BiqRecipe) -> Bool {
		return lhs.uri == rhs.uri
	}


	enum CodingKeys: String, CodingKey {
		case uri
		case title
		case author
		case description

		case tags
		case thresholds
		case medium
	}

	public init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		uri = try values.decode(String.self, forKey: .uri)
		title = try values.decode(String.self, forKey: .title)
		author = try values.decode(String.self, forKey: .author)
		description = try values.decode(String.self, forKey: .description)

		// don't have to decode those non-native properties
		do {
			self.tags = try values.decode([BiqRecipeTag].self, forKey: .tags)
		} catch {

		}
		do {
			self.thresholds = try values.decode([BiqThreshold].self, forKey: .thresholds)
		} catch {

		}
		do {
			self.medium = try values.decode([BiqRecipeMedia].self, forKey: .medium)
		} catch {

		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(uri, forKey: .uri)
		try container.encode(title, forKey: .title)
		try container.encode(author, forKey: .author)
		try container.encode(description, forKey: .description)
		try container.encode(tags, forKey: .tags)
		try container.encode(thresholds, forKey: .thresholds)
		try container.encode(medium, forKey: .medium)
	}

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

	private func writeProperties<T: Codable>(batch: [T], filter: CRUDBooleanExpression) {
		guard let db = BiqRecipe.pdb else { return }
		let table = db.table(T.self)
		do {
			try db.transaction {
				try table.where(filter).delete()
				for element in (batch.compactMap { $0 }) {
					try table.insert(element)
				}
			}
		} catch (let err) {
			CRUDLogging.log(.error, "unable to write properties because \(err)")
		}
	}

	public func add<T: Codable>(property: T) -> Bool {
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

	public func del<T: Codable>(`type`: T.Type, condition: CRUDBooleanExpression) -> Bool {
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

	/// all tags associated to this recipe
	public var tags: [BiqRecipeTag] {
		get {
			return readProperties(filter: \BiqRecipeTag.uri == self.uri)
		}
		set {
			let values = newValue.filter { !$0.uri.isEmpty }
			if values.isEmpty {
				guard let db = BiqRecipe.pdb else { return }
				let table = db.table(BiqRecipeTag.self)
				_ = try? table.where(\BiqRecipeTag.uri == self.uri).delete()
			} else {
				writeProperties(batch: values, filter: \BiqRecipeTag.uri == self.uri)
			}
		}
	}

	/// all thresholds associated to this recipe
	public var thresholds: [BiqThreshold] {
		get {
			return readProperties(filter: \BiqThreshold.uri == self.uri)
		}
		set {
			let values = newValue.filter { !$0.uri.isEmpty }
			if values.isEmpty {
				guard let db = BiqRecipe.pdb else { return }
				let table = db.table(BiqThreshold.self)
				_ = try? table.where(\BiqThreshold.uri == self.uri).delete()
			} else {
				writeProperties(batch: values, filter: \BiqThreshold.uri == self.uri)
			}
		}
	}

	/// all media attachments associated to this recipe
	public var medium: [BiqRecipeMedia] {
		get {
			return readProperties(filter: \BiqRecipeMedia.uri == self.uri)
		}
		set {
			let values = newValue.filter { !$0.uri.isEmpty }
			if values.isEmpty {
				guard let db = BiqRecipe.pdb else { return }
				let table = db.table(BiqRecipeMedia.self)
				_ = try? table.where(\BiqRecipeMedia.uri == self.uri).delete()
			} else {
				writeProperties(batch: values, filter: \BiqRecipeMedia.uri == self.uri)
			}
		}
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

	public static func < (lhs: BiqRecipe, rhs: BiqRecipe) -> Bool {
		return lhs.uri == rhs.uri
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

	static func recipeGet(session rs: RequestSession) throws -> BiqRecipe? {
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
		return BiqRecipeResult(1)
	}

	static func recipeTagAdd(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let tags = try JSONDecoder().decode([BiqRecipeTag].self, from: Data(postBody))
		guard let prime = tags.first, let recipe = BiqRecipe(uri: prime.uri) else {
			throw HTTPResponseError(status: .badRequest, description: "Blank post")
		}
		let results = tags.map { recipe.add(property: $0) ? 1 : 0 }
		let total = results.reduce(0) { $0 + $1 }
		return BiqRecipeResult(total)
	}

	static func recipeTagRemove(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let tags = try JSONDecoder().decode([BiqRecipeTag].self, from: Data(postBody))
		guard let prime = tags.first, let recipe = BiqRecipe(uri: prime.uri) else {
			throw HTTPResponseError(status: .badRequest, description: "Blank post")
		}
		let results = tags.map { recipe.del(type: BiqRecipeTag.self, condition: \BiqRecipeTag.uri == prime.uri && \BiqRecipeTag.tag == $0.tag) ? 1 : 0 }
		let total = results.reduce(0) { $0 + $1 }
		return BiqRecipeResult(total)
	}

	static func recipeTagSet(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let tags = try JSONDecoder().decode([BiqRecipeTag].self, from: Data(postBody))
		guard let prime = tags.first, var recipe = BiqRecipe(uri: prime.uri) else {
			throw HTTPResponseError(status: .badRequest, description: "Blank post")
		}
		recipe.tags = tags
		return BiqRecipeResult(recipe.tags.count)
	}

	static func recipeTagGet(session rs: RequestSession) throws -> [String] {
		guard let uri = rs.request.param(name: "uri"), let recipe = BiqRecipe(uri: uri) else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid recipe uri.")
		}
		return recipe.tags.map { $0.tag }
	}

	static func recipeMediaAdd(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let medium = try JSONDecoder().decode([BiqRecipeMedia].self, from: Data(postBody))
		guard let prime = medium.first, let recipe = BiqRecipe(uri: prime.uri) else {
			throw HTTPResponseError(status: .badRequest, description: "Blank post")
		}
		let results = medium.map { recipe.add(property: $0) ? 1 : 0 }
		let total = results.reduce(0) { $0 + $1 }
		return BiqRecipeResult(total)
	}

	static func recipeMediaRemove(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let medium = try JSONDecoder().decode([BiqRecipeMedia].self, from: Data(postBody))
		guard let prime = medium.first, let recipe = BiqRecipe(uri: prime.uri) else {
			throw HTTPResponseError(status: .badRequest, description: "Blank post")
		}
		let results = medium.map { recipe.del(type: BiqRecipeMedia.self, condition: \BiqRecipeMedia.uri == prime.uri && \BiqRecipeMedia.title == $0.title) ? 1 : 0 }
		let total = results.reduce(0) { $0 + $1 }
		return BiqRecipeResult(total)
	}

	static func recipeMediaSet(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let medium = try JSONDecoder().decode([BiqRecipeMedia].self, from: Data(postBody))
		guard let prime = medium.first, var recipe = BiqRecipe(uri: prime.uri) else {
			throw HTTPResponseError(status: .badRequest, description: "Blank post")
		}
		recipe.medium = medium
		return BiqRecipeResult(recipe.medium.count)
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
		guard let prime = thresholds.first, let recipe = BiqRecipe(uri: prime.uri) else {
			throw HTTPResponseError(status: .badRequest, description: "Blank post")
		}
		let results = thresholds.map { recipe.add(property: $0) ? 1 : 0 }
		let total = results.reduce(0) { $0 + $1 }
		return BiqRecipeResult(total)
	}

	static func recipeThresholdRemove(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let thresholds = try JSONDecoder().decode([BiqThreshold].self, from: Data(postBody))
		guard let prime = thresholds.first, let recipe = BiqRecipe(uri: prime.uri) else {
			throw HTTPResponseError(status: .badRequest, description: "Blank post")
		}
		let results = thresholds.map { recipe.del(type: BiqThreshold.self, condition: \BiqThreshold.uri == prime.uri && \BiqThreshold.measurement == $0.measurement) ? 1 : 0 }
		let total = results.reduce(0) { $0 + $1 }
		return BiqRecipeResult(total)
	}

	static func recipeThresholdSet(session rs: RequestSession) throws -> BiqRecipeResult {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let thresholds = try JSONDecoder().decode([BiqThreshold].self, from: Data(postBody))
		guard let prime = thresholds.first, var recipe = BiqRecipe(uri: prime.uri) else {
			throw HTTPResponseError(status: .badRequest, description: "Blank post")
		}
		recipe.thresholds = thresholds
		return BiqRecipeResult(recipe.thresholds.count)
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
