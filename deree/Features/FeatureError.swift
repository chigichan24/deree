enum FeatureError: Equatable, Sendable {
    case storageFailed(StorageError)
    case clipboardFailed(ClipboardError)
}
