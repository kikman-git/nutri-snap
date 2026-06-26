import SwiftUI

enum BrandIcon {
    struct Trends: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 4, y: 16))
            p.addCurve(to: CGPoint(x: 12, y: 8),
                       control1: CGPoint(x: 8, y: 14), control2: CGPoint(x: 9, y: 8))
            p.addCurve(to: CGPoint(x: 20, y: 13),
                       control1: CGPoint(x: 15, y: 8), control2: CGPoint(x: 16, y: 13))
            p.move(to: CGPoint(x: 4, y: 20))
            p.addLine(to: CGPoint(x: 20, y: 20))
            return p.applying(gridScale(rect))
        }
    }

    struct Journal: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.addRoundedRect(in: CGRect(x: 4, y: 5.5, width: 16, height: 14.5),
                             cornerSize: CGSize(width: 3.2, height: 3.2))
            p.move(to: CGPoint(x: 4, y: 9.5));  p.addLine(to: CGPoint(x: 20, y: 9.5))
            p.move(to: CGPoint(x: 8.5, y: 3.5)); p.addLine(to: CGPoint(x: 8.5, y: 6.5))
            p.move(to: CGPoint(x: 15.5, y: 3.5)); p.addLine(to: CGPoint(x: 15.5, y: 6.5))
            return p.applying(gridScale(rect))
        }
    }

    struct Camera: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 3, y: 8.5))
            p.addArc(tangent1End: CGPoint(x: 3, y: 6.5), tangent2End: CGPoint(x: 7, y: 6.5), radius: 2)
            p.addLine(to: CGPoint(x: 7, y: 6.5))
            p.addLine(to: CGPoint(x: 8.3, y: 4.5))
            p.addLine(to: CGPoint(x: 13.7, y: 4.5))
            p.addLine(to: CGPoint(x: 15, y: 6.5))
            p.addLine(to: CGPoint(x: 17, y: 6.5))
            p.addArc(tangent1End: CGPoint(x: 19, y: 6.5), tangent2End: CGPoint(x: 19, y: 16.5), radius: 2)
            p.addArc(tangent1End: CGPoint(x: 19, y: 18.5), tangent2End: CGPoint(x: 5, y: 18.5), radius: 2)
            p.addArc(tangent1End: CGPoint(x: 3, y: 18.5), tangent2End: CGPoint(x: 3, y: 8.5), radius: 2)
            p.closeSubpath()
            p.addEllipse(in: CGRect(x: 12 - 3.4, y: 12.5 - 3.4, width: 6.8, height: 6.8))
            return p.applying(gridScale(rect))
        }
    }
}

private func gridScale(_ rect: CGRect) -> CGAffineTransform {
    CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24)
}
