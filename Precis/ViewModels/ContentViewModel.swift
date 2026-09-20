import Foundation
import SwiftUI

@MainActor
public final class ContentViewModel: ObservableObject {
    @Published public var appTitle = "Precis"
    @Published public var statusText = "Architecture ready"

    public init() {}
}
