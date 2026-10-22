import Foundation
import SwiftUI

@propertyWrapper
public struct UserDefaultsStorage<Value> {
    private let key: String
    private let defaultValue: Value

    public init(wrappedValue: Value, _ key: String) {
        self.key = key
        defaultValue = wrappedValue
    }

    public var wrappedValue: Value {
        get {
            UserDefaults.standard.object(forKey: key) as? Value ?? defaultValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}
