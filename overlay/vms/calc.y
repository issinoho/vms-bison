/* calc.y - a small calculator grammar for the OpenVMS smoke test.  */
%{
#include <stdio.h>
#include <ctype.h>
int yylex (void);
void yyerror (char const *);
static char const *input;
%}
%define api.value.type {long}
%token NUM
%left '+' '-'
%left '*' '/'
%%
line: expr                { printf ("%ld\n", $1); }
    ;
expr: expr '+' expr       { $$ = $1 + $3; }
    | expr '-' expr       { $$ = $1 - $3; }
    | expr '*' expr       { $$ = $1 * $3; }
    | expr '/' expr       { $$ = $1 / $3; }
    | '(' expr ')'        { $$ = $2; }
    | NUM
    ;
%%
int
yylex (void)
{
  while (*input == ' ')
    input++;
  if (isdigit ((unsigned char) *input))
    {
      long n = 0;
      while (isdigit ((unsigned char) *input))
        n = 10 * n + (*input++ - '0');
      yylval = n;
      return NUM;
    }
  return *input ? *input++ : 0;
}

void
yyerror (char const *msg)
{
  fprintf (stderr, "%s\n", msg);
}

int
main (int argc, char **argv)
{
  input = argc > 1 ? argv[1] : "2+3*4";
  return yyparse ();
}
