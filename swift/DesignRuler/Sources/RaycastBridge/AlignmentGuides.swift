import Foundation
import RaycastSwiftMacros
import DesignRulerCore

@raycast func alignmentGuides(hideHintBar: Bool) {
    AlignmentGuidesCoordinator.shared.run(hideHintBar: hideHintBar)
}
