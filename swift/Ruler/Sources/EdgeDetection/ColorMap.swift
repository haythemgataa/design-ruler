import Foundation

class ColorMap {
    let width: Int
    let height: Int
    let pixels: [UInt8]  // RGBA, 4 bytes per pixel
    let screenFrame: CGRect  // AX coords: which screen area this covers
    let scale: CGFloat  // pixel-to-point ratio (2.0 on Retina)

    init(width: Int, height: Int, pixels: [UInt8], screenFrame: CGRect) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.screenFrame = screenFrame
        self.scale = CGFloat(width) / screenFrame.width
    }

    /// Scan from a screen point (AX coords) in 4 cardinal directions.
    func scan(from point: CGPoint, tolerance: UInt8 = 1,
              skipLeft: Int = 0, skipRight: Int = 0,
              skipTop: Int = 0, skipBottom: Int = 0,
              includeBorders: Bool = true) -> DirectionalEdges {
        let px = min(max(Int((point.x - screenFrame.origin.x) * scale), 0), width - 1)
        let py = min(max(Int((point.y - screenFrame.origin.y) * scale), 0), height - 1)

        let refIdx = (py * width + px) * 4
        let refR = pixels[refIdx]
        let refG = pixels[refIdx + 1]
        let refB = pixels[refIdx + 2]

        let leftHit = scanDirection(fromX: px, fromY: py, dx: -1, dy: 0,
                                     refR: refR, refG: refG, refB: refB,
                                     tolerance: tolerance, skipCount: skipLeft,
                                     includeBorders: includeBorders)
        let rightHit = scanDirection(fromX: px, fromY: py, dx: 1, dy: 0,
                                      refR: refR, refG: refG, refB: refB,
                                      tolerance: tolerance, skipCount: skipRight,
                                      includeBorders: includeBorders)
        let topHit = scanDirection(fromX: px, fromY: py, dx: 0, dy: -1,
                                    refR: refR, refG: refG, refB: refB,
                                    tolerance: tolerance, skipCount: skipTop,
                                    includeBorders: includeBorders)
        let bottomHit = scanDirection(fromX: px, fromY: py, dx: 0, dy: 1,
                                       refR: refR, refG: refG, refB: refB,
                                       tolerance: tolerance, skipCount: skipBottom,
                                       includeBorders: includeBorders)

        return DirectionalEdges(cursorPosition: point,
                                left: leftHit, right: rightHit,
                                top: topHit, bottom: bottomHit)
    }

    /// Scan in one direction using color comparison with stabilization.
    private func scanDirection(fromX: Int, fromY: Int, dx: Int, dy: Int,
                               refR: UInt8, refG: UInt8, refB: UInt8,
                               tolerance: UInt8, skipCount: Int = 0,
                               includeBorders: Bool = true) -> EdgeHit? {
        let isHorizontal = dx != 0
        let stabilizationNeeded = 3
        let stabilizationTolerance = 3

        var x = fromX + dx
        var y = fromY + dy

        // Mutable reference color — updated after each skip
        var curRefR = refR
        var curRefG = refG
        var curRefB = refB

        var edgesFound = 0
        var inEdgeTransition = false
        var stableCount = 0

        var candR: UInt8 = 0
        var candG: UInt8 = 0
        var candB: UInt8 = 0

        while x >= 0, x < width, y >= 0, y < height {
            let idx = (y * width + x) * 4
            let r = pixels[idx]
            let g = pixels[idx + 1]
            let b = pixels[idx + 2]

            let dR = abs(Int(r) - Int(curRefR))
            let dG = abs(Int(g) - Int(curRefG))
            let dB = abs(Int(b) - Int(curRefB))
            let exceeds = max(dR, max(dG, dB)) > Int(tolerance)

            if !inEdgeTransition {
                if exceeds {
                    if edgesFound < skipCount {
                        // Edge we need to skip — enter transition mode
                        inEdgeTransition = true
                        stableCount = 0
                    } else {
                        // Edge we want to return
                        var finalX = x
                        var finalY = y

                        // Peek: absorb 1-CSS-px border if enabled.
                        // On Retina (2x), CSS 1px = 2 device pixels, so peek `scale` pixels ahead.
                        if includeBorders {
                            let borderWidth = max(Int(scale.rounded()), 1)
                            let peekX = x + dx * borderWidth
                            let peekY = y + dy * borderWidth
                            if peekX >= 0, peekX < width, peekY >= 0, peekY < height {
                                let peekIdx = (peekY * width + peekX) * 4
                                let pR = pixels[peekIdx], pG = pixels[peekIdx + 1], pB = pixels[peekIdx + 2]
                                let bdr = max(abs(Int(pR) - Int(r)), abs(Int(pG) - Int(g)), abs(Int(pB) - Int(b)))
                                if bdr > Int(tolerance) {
                                    // Pixel past the border differs from edge pixel → border is 1 CSS px → absorb
                                    finalX = peekX
                                    finalY = peekY
                                }
                            }
                        }

                        let distance = CGFloat(isHorizontal ? abs(finalX - fromX) : abs(finalY - fromY)) / scale
                        let screenPos: CGFloat
                        if isHorizontal {
                            screenPos = screenFrame.origin.x + CGFloat(finalX) / scale
                        } else {
                            screenPos = screenFrame.origin.y + CGFloat(finalY) / scale
                        }
                        let absorbed = (finalX != x || finalY != y)
                        return EdgeHit(distance: distance, screenPosition: screenPos, borderAbsorbed: absorbed)
                    }
                }
            } else {
                // In edge transition: stabilize to find new region
                if stableCount == 0 {
                    // First pixel after entering transition — start candidate
                    candR = r
                    candG = g
                    candB = b
                    stableCount = 1
                } else {
                    let dCR = abs(Int(r) - Int(candR))
                    let dCG = abs(Int(g) - Int(candG))
                    let dCB = abs(Int(b) - Int(candB))
                    let candidateExceeds = max(dCR, max(dCG, dCB)) > stabilizationTolerance

                    if !candidateExceeds {
                        stableCount += 1
                        if stableCount >= stabilizationNeeded {
                            // Stable new region found
                            curRefR = candR
                            curRefG = candG
                            curRefB = candB
                            edgesFound += 1
                            inEdgeTransition = false
                            stableCount = 0
                        }
                    } else {
                        // Color changed again — restart candidate
                        candR = r
                        candG = g
                        candB = b
                        stableCount = 1
                    }
                }
            }

            x += dx
            y += dy
        }

        return nil
    }
}
