import Foundation

public struct NcodePoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct UnitPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public enum CalibrationError: Error, Equatable {
    case requiresFourCorners
    case degenerateGeometry
}

public struct ProjectiveTransform: Codable, Equatable, Sendable {
    private let coefficients: [Double]

    public init(
        source: [NcodePoint],
        destination: [UnitPoint]
    ) throws {
        guard source.count == 4, destination.count == 4 else {
            throw CalibrationError.requiresFourCorners
        }

        var matrix: [[Double]] = []
        for (point, target) in zip(source, destination) {
            matrix.append([
                point.x,
                point.y,
                1,
                0,
                0,
                0,
                -target.x * point.x,
                -target.x * point.y,
                target.x,
            ])
            matrix.append([
                0,
                0,
                0,
                point.x,
                point.y,
                1,
                -target.y * point.x,
                -target.y * point.y,
                target.y,
            ])
        }

        let solution = try Self.solve(matrix)
        coefficients = solution + [1]
    }

    public func map(_ point: NcodePoint) -> UnitPoint? {
        let denominator = coefficients[6] * point.x
            + coefficients[7] * point.y
            + coefficients[8]
        guard abs(denominator) > 0.000_000_001 else {
            return nil
        }

        return UnitPoint(
            x: (
                coefficients[0] * point.x
                    + coefficients[1] * point.y
                    + coefficients[2]
            ) / denominator,
            y: (
                coefficients[3] * point.x
                    + coefficients[4] * point.y
                    + coefficients[5]
            ) / denominator
        )
    }

    private static func solve(_ augmentedMatrix: [[Double]]) throws -> [Double] {
        var matrix = augmentedMatrix
        let dimension = 8

        for column in 0..<dimension {
            guard let pivotRow = (column..<dimension).max(by: {
                abs(matrix[$0][column]) < abs(matrix[$1][column])
            }),
            abs(matrix[pivotRow][column]) > 0.000_000_001
            else {
                throw CalibrationError.degenerateGeometry
            }

            if pivotRow != column {
                matrix.swapAt(pivotRow, column)
            }

            let pivot = matrix[column][column]
            for index in column...dimension {
                matrix[column][index] /= pivot
            }

            for row in 0..<dimension where row != column {
                let factor = matrix[row][column]
                guard factor != 0 else {
                    continue
                }
                for index in column...dimension {
                    matrix[row][index] -= factor * matrix[column][index]
                }
            }
        }

        return (0..<dimension).map { matrix[$0][dimension] }
    }
}

public struct NcodeSurfaceCalibration: Codable, Equatable, Sendable {
    public let corners: [NcodePoint]
    public let transform: ProjectiveTransform

    public var estimatedAspectRatio: Double {
        let top = distance(corners[0], corners[1])
        let bottom = distance(corners[3], corners[2])
        let left = distance(corners[0], corners[3])
        let right = distance(corners[1], corners[2])
        return ((top + bottom) / 2) / ((left + right) / 2)
    }

    public init(corners: [NcodePoint]) throws {
        guard corners.count == 4 else {
            throw CalibrationError.requiresFourCorners
        }
        self.corners = corners
        transform = try ProjectiveTransform(
            source: corners,
            destination: [
                UnitPoint(x: 0, y: 0),
                UnitPoint(x: 1, y: 0),
                UnitPoint(x: 1, y: 1),
                UnitPoint(x: 0, y: 1),
            ]
        )
    }

    public func normalize(_ point: NcodePoint) -> UnitPoint? {
        transform.map(point)
    }

    private func distance(_ first: NcodePoint, _ second: NcodePoint) -> Double {
        hypot(second.x - first.x, second.y - first.y)
    }
}
