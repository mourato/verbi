import CoreData

extension NSManagedObject {
    static func resolvedEntityDescription(
        named entityName: String,
        in context: NSManagedObjectContext
    ) -> NSEntityDescription {
        if let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context) {
            return entityDescription
        }

        preconditionFailure("Missing Core Data entity description for \(entityName)")
    }
}
