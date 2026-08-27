///|
priv enum HighlightKind {
  Keyword
  LowerIdentifier
  UpperIdentifier
  PackageName
  Label
  Number
  String
  Character
  Boolean
  Comment
  Attribute
  Operator
  Punctuation
}

///|
fn Theme::style_for(self : Theme, kind : HighlightKind) -> Style {
  match kind {
    Keyword => self.keyword
    LowerIdentifier => self.lower_identifier
    UpperIdentifier => self.upper_identifier
    PackageName => self.package_name
    Label => self.label
    Number => self.number
    String => self.string
    Character => self.character
    Boolean => self.boolean
    Comment => self.comment
    Attribute => self.attribute
    Operator => self.operator
    Punctuation => self.punctuation
  }
}

///|
fn classify_token(kind : @tokens.TokenKind) -> HighlightKind? {
  match kind {
    TK_CHAR | TK_BYTE => Some(Character)
    TK_INT | TK_FLOAT | TK_DOUBLE | TK_DOT_INT => Some(Number)
    TK_BYTES
    | TK_STRING
    | TK_MULTILINE_STRING
    | TK_MULTILINE_INTERP
    | TK_INTERP
    | TK_BYTES_INTERP
    | TK_REGEX_LITERAL
    | TK_REGEX_INTERP => Some(String)
    TK_ATTRIBUTE => Some(Attribute)
    TK_LIDENT | TK_DOT_LIDENT | TK_UNDERSCORE => Some(LowerIdentifier)
    TK_UIDENT | TK_DOT_UIDENT => Some(UpperIdentifier)
    TK_POST_LABEL | TK_POST_LABEL_TRANSPARENT => Some(Label)
    TK_COMMENT => Some(Comment)
    TK_NEWLINE | TK_EOF => None
    TK_FALSE | TK_TRUE => Some(Boolean)
    TK_INFIX1
    | TK_INFIX2
    | TK_INFIX3
    | TK_INFIX4
    | TK_AUGMENTED_ASSIGNMENT
    | TK_PLUS_EQUAL
    | TK_EQUAL
    | TK_EQ_TILDE
    | TK_MINUS
    | TK_QUESTION
    | TK_EXCLAMATION
    | TK_PLUS
    | TK_BAR
    | TK_AMPERAMPER
    | TK_AMPER
    | TK_CARET
    | TK_BARBAR
    | TK_PIPE
    | TK_PIPE_LEFT
    | TK_LT_PLUS
    | TK_LT_QUESTION
    | TK_FAT_ARROW
    | TK_THIN_ARROW
    | TK_DOTDOT
    | TK_RANGE_INCLUSIVE
    | TK_RANGE_LT_INCLUSIVE
    | TK_RANGE_EXCLUSIVE
    | TK_RANGE_INCLUSIVE_REV
    | TK_RANGE_EXCLUSIVE_REV
    | TK_ELLIPSIS
    | TK_IMPLIES => Some(Operator)
    TK_LPAREN
    | TK_RPAREN
    | TK_COMMA
    | TK_DOT_LPAREN
    | TK_COLONCOLON
    | TK_COLON
    | TK_SEMI
    | TK_LBRACKET
    | TK_LBRACKET_BAR
    | TK_RBRACKET
    | TK_BAR_RBRACKET
    | TK_LBRACE
    | TK_RBRACE => Some(Punctuation)
    TK_PACKAGE_NAME => Some(PackageName)
    TK_PUB
    | TK_PRIV
    | TK_READONLY
    | TK_IMPORT
    | TK_EXTERN
    | TK_BREAK
    | TK_CONTINUE
    | TK_STRUCT
    | TK_ENUM
    | TK_TRAIT
    | TK_DERIVE
    | TK_IMPL
    | TK_WITH
    | TK_RAISE
    | TK_THROW
    | TK_TRY
    | TK_CATCH
    | TK_ASYNC
    | TK_TYPEALIAS
    | TK_TRAITALIAS
    | TK_FNALIAS
    | TK_AS
    | TK_ELSE
    | TK_FN
    | TK_IF
    | TK_LET
    | TK_PROOF_ASSERT
    | TK_PROOF_LET
    | TK_CONST
    | TK_MATCH
    | TK_USING
    | TK_MUTABLE
    | TK_TYPE
    | TK_WHILE
    | TK_RETURN
    | TK_TEST
    | TK_LOOP
    | TK_GUARD
    | TK_GUARD_EXCLAMATION
    | TK_DEFER
    | TK_FOR
    | TK_IN
    | TK_IS
    | TK_SUBERROR
    | TK_AND
    | TK_FORALL
    | TK_EXISTS
    | TK_LETREC
    | TK_ENUMVIEW
    | TK_EXTENUM
    | TK_DECLARE
    | TK_NORAISE
    | TK_NOBREAK
    | TK_WHERE
    | TK_TRY_QUESTION
    | TK_TRY_EXCLAMATION
    | TK_LEXMATCH
    | TK_LEXMATCH_QUESTION
    | TK_LEXSCAN
    | TK_EXTEND
    | TK_PACKAGE => Some(Keyword)
  }
}
