import Foundation

class CriticMarkupRenderer {
    static func renderCriticMarkup(_ input: String) -> String {
        var output = input
        let addPattern = try! NSRegularExpression(
            pattern: #"\{\+\+(?<value>.*?)\+\+[ \t]*(?:\[(?<meta>.*?)\])?[ \t]*\}"#,
            options: [.dotMatchesLineSeparators])
        let delPattern = try! NSRegularExpression(
            pattern: #"\{--(?<value>.*?)--[ \t]*(?:\[(?<meta>.*?)\])?[ \t]*\}"#,
            options: [.dotMatchesLineSeparators])
        let subsPattern = try! NSRegularExpression(
            pattern:
                #"\{~~(?<original>(?:[^~>]|(?:~(?!>)))+)~>(?<new>(?:[^~]+|(?:~(?!~\})))+)~~\}"#,
            options: [.dotMatchesLineSeparators])
        let commPattern = try! NSRegularExpression(
            pattern: #"\{>>(.*?)<<\}"#, options: [.dotMatchesLineSeparators])
        let insdelCommPattern = try! NSRegularExpression(
            pattern: #"(?<=[-+=~<]\})[ \t]*\{>>(.*?)?<<\}"#, options: [.dotMatchesLineSeparators])
        let markPattern = try! NSRegularExpression(
            pattern: #"\{==(.*?)==\}"#, options: [.dotMatchesLineSeparators])

        var subCounter = 0

        func replace(
            _ regex: NSRegularExpression, in string: String,
            using block: (NSTextCheckingResult, String) -> String
        ) -> String {
            var result = ""
            var lastIndex = string.startIndex
            let nsString = string as NSString
            let matches = regex.matches(
                in: string, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                let range = Range(match.range, in: string)!
                result += String(string[lastIndex..<range.lowerBound])
                result += block(match, string)
                lastIndex = range.upperBound
            }
            result += String(string[lastIndex...])
            return result
        }

        // insdel_comm_pattern
        output = replace(insdelCommPattern, in: output) { match, str in
            let value =
                match.range(at: 1).location != NSNotFound
                ? (str as NSString).substring(with: match.range(at: 1)) : ""
            let content = value.replacingOccurrences(of: "\n", with: " ")
            return
                "<span class=\"critic criticcomment inline\" data-comment=\"\(content)\">&dagger;</span>"
        }

        // del_pattern
        output = replace(delPattern, in: output) { match, str in
            let value =
                match.range(withName: "value").location != NSNotFound
                ? (str as NSString).substring(with: match.range(withName: "value")) : ""
            if value == "\n\n" {
                return "<del>&nbsp;</del>"
            } else {
                let parts = value.components(separatedBy: "\n\n")
                return parts.map { "<del class=\"crit\">\($0)</del>" }.joined(separator: "\n\n")
            }
        }

        // add_pattern
        output = replace(addPattern, in: output) { match, str in
            let value =
                match.range(withName: "value").location != NSNotFound
                ? (str as NSString).substring(with: match.range(withName: "value")) : ""
            if value.hasPrefix("\n\n") && value != "\n\n" {
                let replace =
                    "\n\n<span style=\"display:none\"></span><ins class=\"crit criticbreak\">&nbsp;</ins>\n\n"
                let parts = value.components(separatedBy: "\n\n")
                let insParts = parts.map { "<ins class=\"crit\">\($0)</ins>" }
                return replace + insParts.joined(separator: "\n\n")
            } else if value == "\n\n" {
                return
                    "\n\n<span style=\"display:none\"></span><ins class=\"crit criticbreak\">&nbsp;</ins>\n\n"
            } else if value.hasSuffix("\n\n") && value != "\n\n" {
                let parts = value.components(separatedBy: "\n\n")
                let insParts = parts.map { "<ins class=\"crit\">\($0)</ins>" }
                return insParts.joined(separator: "\n\n")
                    + "\n\n<span style=\"display:none\"></span><ins class=\"crit criticbreak\">&nbsp;</ins>\n\n"
            } else {
                let parts = value.components(separatedBy: "\n\n")
                let insParts = parts.map { "<ins class=\"crit\">\($0)</ins>" }
                return insParts.joined(separator: "\n\n")
            }
        }

        // comm_pattern
        output = replace(commPattern, in: output) { match, str in
            let value =
                match.range(at: 1).location != NSNotFound
                ? (str as NSString).substring(with: match.range(at: 1)) : ""
            let content = value.replacingOccurrences(of: "\n", with: " ")
            return "<span class=\"critic criticcomment\">\(content)</span>"
        }

        // mark_pattern
        output = replace(markPattern, in: output) { match, str in
            let value =
                match.range(at: 1).location != NSNotFound
                ? (str as NSString).substring(with: match.range(at: 1)) : ""
            return "<mark class=\"crit\">\(value)</mark>"
        }

        // add_pattern again (as in Ruby)
        output = replace(addPattern, in: output) { match, str in
            let value =
                match.range(withName: "value").location != NSNotFound
                ? (str as NSString).substring(with: match.range(withName: "value")) : ""
            if value.hasPrefix("\n\n") && value != "\n\n" {
                let replace =
                    "\n\n<span style=\"display:none\"></span><ins class=\"crit criticbreak\">&nbsp;</ins>\n\n"
                let parts = value.components(separatedBy: "\n\n")
                let insParts = parts.map { "<ins class=\"crit\">\($0)</ins>" }
                return replace + insParts.joined(separator: "\n\n")
            } else if value == "\n\n" {
                return
                    "\n\n<span style=\"display:none\"></span><ins class=\"crit criticbreak\">&nbsp;</ins>\n\n"
            } else if value.hasSuffix("\n\n") && value != "\n\n" {
                let parts = value.components(separatedBy: "\n\n")
                let insParts = parts.map { "<ins class=\"crit\">\($0)</ins>" }
                return insParts.joined(separator: "\n\n")
                    + "\n\n<span style=\"display:none\"></span><ins class=\"crit criticbreak\">&nbsp;</ins>\n\n"
            } else {
                let parts = value.components(separatedBy: "\n\n")
                let insParts = parts.map { "<ins class=\"crit\">\($0)</ins>" }
                return insParts.joined(separator: "\n\n")
            }
        }

        // subs_pattern
        output = replace(subsPattern, in: output) { match, str in
            subCounter += 1
            let original =
                match.range(withName: "original").location != NSNotFound
                ? (str as NSString).substring(with: match.range(withName: "original")) : ""
            let newVal =
                match.range(withName: "new").location != NSNotFound
                ? (str as NSString).substring(with: match.range(withName: "new")) : ""
            let delString = "<del class=\"crit\" data-subout=\"sub\(subCounter)\">\(original)</del>"
            let insString = "<ins class=\"crit\" id=\"sub\(subCounter)\">\(newVal)</ins>"
            return delString + insString
        }

        return output
    }
}
