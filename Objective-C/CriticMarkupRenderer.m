#import "CriticMarkupRenderer.h"

// Helper function to replace regex matches with a block
static NSString *
ReplaceWithBlock(NSRegularExpression *regex, NSString *input,
                 NSString * (^block)(NSTextCheckingResult *result)) {
  NSMutableString *resultString = [NSMutableString string];
  __block NSUInteger lastLocation = 0;
  [regex enumerateMatchesInString:input
                          options:0
                            range:NSMakeRange(0, input.length)
                       usingBlock:^(NSTextCheckingResult *match,
                                    NSMatchingFlags flags, BOOL *stop) {
                         if (!match)
                           return;
                         NSRange matchRange = match.range;
                         if (matchRange.location > lastLocation) {
                           [resultString
                               appendString:[input substringWithRange:
                                                       NSMakeRange(
                                                           lastLocation,
                                                           matchRange.location -
                                                               lastLocation)]];
                         }
                         NSString *replacement = block(match);
                         if (replacement) {
                           [resultString appendString:replacement];
                         }
                         lastLocation = matchRange.location + matchRange.length;
                       }];
  if (lastLocation < input.length) {
    [resultString appendString:[input substringFromIndex:lastLocation]];
  }
  return resultString;
}

@implementation CriticMarkupRenderer

+ (NSString *)renderCriticMarkup:(NSString *)input {
  if (!input)
    return @"";
  NSString *output = [input copy];
  static NSRegularExpression *addPattern, *delPattern, *subsPattern,
      *commPattern, *insdelCommPattern, *markPattern;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    addPattern = [NSRegularExpression
        regularExpressionWithPattern:@"\\{\\+\\+(?<value>.*?)\\+\\+[ "
                                     @"\\t]*(?:\\[(?<meta>.*?)\\])?[ \\t]*\\}"
                             options:NSRegularExpressionDotMatchesLineSeparators
                               error:nil];
    delPattern = [NSRegularExpression
        regularExpressionWithPattern:
            @"\\{--(?<value>.*?)--[ \\t]*(?:\\[(?<meta>.*?)\\])?[ \\t]*\\}"
                             options:NSRegularExpressionDotMatchesLineSeparators
                               error:nil];
    subsPattern = [NSRegularExpression
        regularExpressionWithPattern:@"\\{~~(?<original>(?:[^~>]|(?:~(?!>)))+)~"
                                     @">(?<new>(?:[^~]+|(?:~(?!~\\})))+)~~\\}"
                             options:NSRegularExpressionDotMatchesLineSeparators
                               error:nil];
    commPattern = [NSRegularExpression
        regularExpressionWithPattern:@"\\{>>(?<value>.*?)<<\\}"
                             options:NSRegularExpressionDotMatchesLineSeparators
                               error:nil];
    insdelCommPattern = [NSRegularExpression
        regularExpressionWithPattern:
            @"(?<=[-+=~<]\\})[ \\t]*\\{>>(?<value>.*?)?<<\\}"
                             options:NSRegularExpressionDotMatchesLineSeparators
                               error:nil];
    markPattern = [NSRegularExpression
        regularExpressionWithPattern:@"\\{==(?<value>.*?)==\\}"
                             options:NSRegularExpressionDotMatchesLineSeparators
                               error:nil];
  });

  // Substitution counter
  __block NSInteger subCounter = 0;

  // Helper blocks
  NSString * (^deletionProcess)(NSString *) = ^NSString *(NSString *value) {
    if ([value isEqualToString:@"\n\n"]) {
      return @"<del>&nbsp;</del>";
    } else {
      NSArray *parts = [value componentsSeparatedByString:@"\n\n"];
      NSMutableArray *delParts = [NSMutableArray arrayWithCapacity:parts.count];
      for (NSString *part in parts) {
        [delParts
            addObject:[NSString
                          stringWithFormat:@"<del class=\"crit\">%@</del>",
                                           part]];
      }
      return [delParts componentsJoinedByString:@"\n\n"];
    }
  };

  NSString * (^additionProcess)(NSString *) = ^NSString *(NSString *value) {
    if ([value hasPrefix:@"\n\n"] && ![value isEqualToString:@"\n\n"]) {
      NSString *replace = @"\n\n<span style=\"display:none\"></span><ins "
                          @"class=\"crit criticbreak\">&nbsp;</ins>\n\n";
      NSArray *parts = [value componentsSeparatedByString:@"\n\n"];
      NSMutableArray *insParts = [NSMutableArray arrayWithCapacity:parts.count];
      for (NSString *part in parts) {
        [insParts
            addObject:[NSString
                          stringWithFormat:@"<ins class=\"crit\">%@</ins>",
                                           part]];
      }
      return [NSString
          stringWithFormat:@"%@%@", replace,
                           [insParts componentsJoinedByString:@"\n\n"]];
    } else if ([value isEqualToString:@"\n\n"]) {
      return @"\n\n<span style=\"display:none\"></span><ins class=\"crit "
             @"criticbreak\">&nbsp;</ins>\n\n";
    } else if ([value hasSuffix:@"\n\n"] && ![value isEqualToString:@"\n\n"]) {
      NSArray *parts = [value componentsSeparatedByString:@"\n\n"];
      NSMutableArray *insParts = [NSMutableArray arrayWithCapacity:parts.count];
      for (NSString *part in parts) {
        [insParts
            addObject:[NSString
                          stringWithFormat:@"<ins class=\"crit\">%@</ins>",
                                           part]];
      }
      return [NSString
          stringWithFormat:@"%@\n\n<span style=\"display:none\"></span><ins "
                           @"class=\"crit criticbreak\">&nbsp;</ins>\n\n",
                           [insParts componentsJoinedByString:@"\n\n"]];
    } else {
      NSArray *parts = [value componentsSeparatedByString:@"\n\n"];
      NSMutableArray *insParts = [NSMutableArray arrayWithCapacity:parts.count];
      for (NSString *part in parts) {
        [insParts
            addObject:[NSString
                          stringWithFormat:@"<ins class=\"crit\">%@</ins>",
                                           part]];
      }
      return [insParts componentsJoinedByString:@"\n\n"];
    }
  };

  NSString * (^subsProcess)(NSString *, NSString *) = ^NSString *(
      NSString *original, NSString *newVal) {
    subCounter++;
    NSString *delString = [NSString
        stringWithFormat:@"<del class=\"crit\" data-subout=\"sub%ld\">%@</del>",
                         (long)subCounter, original];
    NSString *insString = [NSString
        stringWithFormat:@"<ins class=\"crit\" id=\"sub%ld\">%@</ins>",
                         (long)subCounter, newVal];
    return [NSString stringWithFormat:@"%@%@", delString, insString];
  };

  NSString * (^insDelHighlightProcess)(NSString *) =
      ^NSString *(NSString *value) {
        NSString *content =
            [value stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        return [NSString
            stringWithFormat:@"<span class=\"critic criticcomment inline\" "
                             @"data-comment=\"%@\">&dagger;</span>",
                             content];
      };

  NSString * (^highlightProcess)(NSString *) = ^NSString *(NSString *value) {
    NSString *content =
        [value stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return [NSString
        stringWithFormat:@"<span class=\"critic criticcomment\">%@</span>",
                         content];
  };

  NSString * (^markProcess)(NSString *) = ^NSString *(NSString *value) {
    return [NSString stringWithFormat:@"<mark class=\"crit\">%@</mark>", value];
  };

  // insdel_comm_pattern
  output = [insdelCommPattern
      stringByReplacingMatchesInString:output
                               options:0
                                 range:NSMakeRange(0, output.length)
                          withTemplate:@"$0"];
  output = ReplaceWithBlock(
      insdelCommPattern, output, ^NSString *(NSTextCheckingResult *result) {
        NSString *value =
            [output substringWithRange:[result rangeWithName:@"value"]];
        return insDelHighlightProcess(value);
      });

  // del_pattern
  output = ReplaceWithBlock(
      delPattern, output, ^NSString *(NSTextCheckingResult *result) {
        NSString *value =
            [output substringWithRange:[result rangeWithName:@"value"]];
        return deletionProcess(value);
      });

  // add_pattern
  output = ReplaceWithBlock(
      addPattern, output, ^NSString *(NSTextCheckingResult *result) {
        NSString *value =
            [output substringWithRange:[result rangeWithName:@"value"]];
        return additionProcess(value);
      });

  // comm_pattern
  output = ReplaceWithBlock(
      commPattern, output, ^NSString *(NSTextCheckingResult *result) {
        NSString *value =
            [output substringWithRange:[result rangeWithName:@"value"]];
        return highlightProcess(value);
      });

  // mark_pattern
  output = ReplaceWithBlock(
      markPattern, output, ^NSString *(NSTextCheckingResult *result) {
        NSString *value =
            [output substringWithRange:[result rangeWithName:@"value"]];
        return markProcess(value);
      });

  // add_pattern again (as in Ruby)
  output = ReplaceWithBlock(
      addPattern, output, ^NSString *(NSTextCheckingResult *result) {
        NSString *value =
            [output substringWithRange:[result rangeWithName:@"value"]];
        return additionProcess(value);
      });

  // subs_pattern
  output = ReplaceWithBlock(
      subsPattern, output, ^NSString *(NSTextCheckingResult *result) {
        NSString *original =
            [output substringWithRange:[result rangeWithName:@"original"]];
        NSString *newVal =
            [output substringWithRange:[result rangeWithName:@"new"]];
        return subsProcess(original, newVal);
      });

  return output;
}

@end