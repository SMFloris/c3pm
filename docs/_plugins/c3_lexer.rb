# frozen_string_literal: true

require "rouge"

module Rouge
  module Lexers
    class C3 < RegexLexer
      title "C3"
      desc "The C3 programming language"
      tag "c3"
      filenames "*.c3", "*.c3i"

      state :root do
        rule %r/\s+/, Text::Whitespace
        rule %r{//.*?$}, Comment::Single
        rule %r{/\*.*?\*/}m, Comment::Multiline
        rule %r{"(?:\\.|[^"\\])*"}, Str::Double
        rule %r{'(?:\\.|[^'\\])'}, Str::Char

        rule %r/\b(?:module|import|fn|struct|enum|union|interface|alias|typedef|faultdef|macro|const|var|static|extern|inline|distinct|attribute)\b/,
             Keyword::Declaration
        rule %r/\b(?:if|else|switch|case|default|for|foreach|while|do|return|break|continue|defer|try|catch|throw|assert)\b/,
             Keyword
        rule %r/\b(?:void|bool|char|ichar|short|ushort|int|uint|long|ulong|int128|uint128|float|double|isz|usz|iptr|uptr|String|ZString|any|typeid)\b/,
             Keyword::Type
        rule %r/\b(?:true|false|null)\b/, Keyword::Constant
        rule %r/@[A-Za-z_][A-Za-z0-9_]*/, Name::Decorator
        rule %r/\b0[xX][0-9A-Fa-f_]+\b/, Num::Hex
        rule %r/\b0[bB][01_]+\b/, Num::Bin
        rule %r/\b\d(?:[\d_]*\.?[\d_]*)(?:[eE][+-]?[\d_]+)?[fFdD]?\b/, Num
        rule %r/[A-Za-z_][A-Za-z0-9_]*/, Name
        rule %r/::|->|=>|==|!=|<=|>=|&&|\|\||<<|>>|\+\+|--|[+\-*\/%=&|^!<>?:~]/, Operator
        rule %r/[{}\[\](),.;]/, Punctuation
      end
    end
  end
end
