import VerbiCoreInfrastructure

/// Presentation options preserve the caller's selection semantics and original values.
enum AIModelPickerOptions {
    static func make(
        options: [EnhancementsProviderModelOption],
        isSelected: (EnhancementsProviderModelOption) -> Bool
    ) -> [ModelPickerOption<EnhancementsProviderModelOption>] {
        options.sorted { lhs, rhs in
            let left = lhs.registrationName ?? lhs.provider.displayName
            let right = rhs.registrationName ?? rhs.provider.displayName
            if left.localizedCaseInsensitiveCompare(right) == .orderedSame {
                return lhs.modelID.localizedCaseInsensitiveCompare(rhs.modelID) == .orderedAscending
            }
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }.map { option in
            let identity = ModelBrand.identity(for: option.provider, modelID: option.modelID)
            return ModelPickerOption(
                id: option.id,
                value: option,
                title: option.modelID,
                groupTitle: option.registrationName ?? option.provider.displayName,
                brand: identity.brand,
                host: identity.host,
                fallbackSymbolName: "brain.head.profile",
                isSelected: isSelected(option)
            )
        }
    }
}
