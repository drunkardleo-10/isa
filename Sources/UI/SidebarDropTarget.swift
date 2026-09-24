import Foundation

enum SidebarDropTarget: Equatable {
    case pinned(index: Int)
    case unpinned(index: Int)
}
