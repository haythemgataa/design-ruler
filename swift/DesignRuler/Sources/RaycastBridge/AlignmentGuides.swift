import Foundation
import RaycastSwiftMacros
import DesignRulerCore

@raycast func alignmentGuides(showHintBar: Bool) {
    AlignmentGuidesCoordinator.shared.run(hideHintBar: !showHintBar)
}
