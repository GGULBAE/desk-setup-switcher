import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: strip-png-metadata.swift <input.png> <output.png>\n", stderr)
    exit(64)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let input = try Data(contentsOf: inputURL)
let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])

guard input.count >= 33, input.prefix(8) == signature else {
    fputs("error: input is not a PNG\n", stderr)
    exit(65)
}

// Release screenshots may retain alpha as source evidence; public derivatives
// and the social preview are opaque. Both must be 8-bit truecolor rather than
// indexed or grayscale data.
guard input[24] == 8, input[25] == 2 || input[25] == 6 else {
    fputs("error: expected 8-bit truecolor RGB or RGBA PNG\n", stderr)
    exit(65)
}

let criticalChunkTypes: Set<String> = ["IHDR", "PLTE", "IDAT", "IEND"]
var output = signature
var offset = 8
var sawEnd = false

while offset + 12 <= input.count {
    let length = input[offset..<(offset + 4)].reduce(0) { value, byte in
        (value << 8) | Int(byte)
    }
    let chunkEnd = offset + 12 + length
    guard chunkEnd <= input.count else {
        fputs("error: truncated PNG chunk\n", stderr)
        exit(65)
    }

    let typeData = input[(offset + 4)..<(offset + 8)]
    guard let type = String(data: typeData, encoding: .ascii) else {
        fputs("error: invalid PNG chunk type\n", stderr)
        exit(65)
    }
    if criticalChunkTypes.contains(type) {
        output.append(input[offset..<chunkEnd])
    }
    offset = chunkEnd

    if type == "IEND" {
        sawEnd = true
        break
    }
}

guard sawEnd else {
    fputs("error: PNG is missing IEND\n", stderr)
    exit(65)
}

try output.write(to: outputURL, options: .atomic)
