/// عقدة في شجرة التعبير الرياضي.
abstract class Expr {
  const Expr();
}

class NumberExpr extends Expr {
  final double value;
  const NumberExpr(this.value);
}

class ConstantExpr extends Expr {
  final String name;
  const ConstantExpr(this.name);
}

class VariableExpr extends Expr {
  final String name;
  const VariableExpr(this.name);
}

class UnaryExpr extends Expr {
  /// '-' أو '+'
  final String op;
  final Expr operand;
  const UnaryExpr(this.op, this.operand);
}

/// عملية لاحقة على التعبير: ! ² ³ % °
class PostfixExpr extends Expr {
  final String op;
  final Expr operand;
  const PostfixExpr(this.op, this.operand);
}

class BinaryExpr extends Expr {
  final String op;
  final Expr left;
  final Expr right;
  const BinaryExpr(this.op, this.left, this.right);
}

class CallExpr extends Expr {
  final String name;
  final List<Expr> args;
  const CallExpr(this.name, this.args);
}
