// JavaScript treats 0, NaN and "" as false; Lua treats them as true. TypeScriptToLua copies
// conditions as they are, so a number or string used as true/false would behave differently in the
// game. This lists every such place in src/ (fix them to an explicit check, e.g. `x !== 0`).
const ts = require('typescript');
const path = require('path');
const config = ts.getParsedCommandLineOfConfigFile(process.argv[2] || path.join(__dirname, '..', 'tsconfig.json'), {}, { ...ts.sys, onUnRecoverableConfigFileDiagnostic: () => {} });
const program = ts.createProgram(config.fileNames, config.options);
const checker = program.getTypeChecker();
const bad = [];

function risky(expr) {
	const type = checker.getTypeAtLocation(expr);
	const parts = type.isUnion() ? type.types : [type];
	const flags = process.env.TRUTHY_NO_ANY ? (ts.TypeFlags.NumberLike | ts.TypeFlags.StringLike) : (ts.TypeFlags.NumberLike | ts.TypeFlags.StringLike | ts.TypeFlags.Any | ts.TypeFlags.Unknown);
	return parts.some((t) => (t.flags & flags) !== 0);
}
function check(expr) {
	if (!expr) return;
	while (ts.isParenthesizedExpression(expr)) expr = expr.expression;
	if (ts.isPrefixUnaryExpression(expr) && expr.operator === ts.SyntaxKind.ExclamationToken) return check(expr.operand);
	if (ts.isBinaryExpression(expr) && (expr.operatorToken.kind === ts.SyntaxKind.AmpersandAmpersandToken || expr.operatorToken.kind === ts.SyntaxKind.BarBarToken)) {
		check(expr.left); check(expr.right); return;
	}
	// a literal default (x || '', x || 0) is the same in both languages
	if (ts.isStringLiteral(expr) || ts.isNumericLiteral(expr) || ts.isNoSubstitutionTemplateLiteral(expr)) return;
	if (risky(expr)) {
		const sf = expr.getSourceFile();
		const { line } = sf.getLineAndCharacterOfPosition(expr.getStart());
		bad.push(`${path.basename(sf.fileName)}:${line + 1}  ${expr.getText()}`);
	}
}
function visit(node) {
	if (ts.isIfStatement(node) || ts.isWhileStatement(node) || ts.isDoStatement(node)) check(node.expression);
	else if (ts.isForStatement(node)) check(node.condition);
	else if (ts.isConditionalExpression(node)) check(node.condition);
	else if (ts.isPrefixUnaryExpression(node) && node.operator === ts.SyntaxKind.ExclamationToken) check(node.operand);
	else if (ts.isBinaryExpression(node) && (node.operatorToken.kind === ts.SyntaxKind.AmpersandAmpersandToken || node.operatorToken.kind === ts.SyntaxKind.BarBarToken)) { check(node.left); check(node.right); }
	ts.forEachChild(node, visit);
}
for (const sf of program.getSourceFiles()) if (!sf.isDeclarationFile && sf.fileName.includes('/src/')) visit(sf);
if (bad.length) { console.log('Numbers/strings used as true/false (wrong in Lua):\n  ' + bad.join('\n  ')); process.exit(1); }
console.log('truthiness: ok');
