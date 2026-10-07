import Foundation
import RaycastSwiftMacros
import DesignRulerCore

@raycast func inspect(showHintBar: Bool, corrections: String) {
    MeasureCoordinator.shared.run(hideHintBar: !showHintBar, corrections: corrections)
}
