import Foundation
import RaycastSwiftMacros
import DesignRulerCore

@raycast func inspect(hideHintBar: Bool, corrections: String) {
    MeasureCoordinator.shared.run(hideHintBar: hideHintBar, corrections: corrections)
}
