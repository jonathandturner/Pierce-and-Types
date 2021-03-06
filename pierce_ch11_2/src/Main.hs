module Main where

import System.IO
import Data.List

type Variable = String
type VarList = [(Variable, Int)]
type Context = [(Variable, Type)]

data Value = Lambda (Variable, Type, Term) | TrueValue | FalseValue | UnitValue | ErrorValue | ValueTerm Term deriving Show
data Type = TFun Type Type | TBool | TUnit | TUnknown deriving (Show, Read, Eq)
data Term = Var Variable | Abs Variable Type Term | App Term Term | Seq Term Term | TrueT | FalseT | UnitT deriving (Show, Read, Eq)

getVarType::Variable->Context->Type
getVarType name vars = 
  let f (vname, _) = (vname == name) in 
    let valueFound = find f vars in
       case valueFound of Just (name, typeId) -> typeId 
                          Nothing -> TUnknown

getVarName::Variable->VarList->Variable
getVarName name vars = 
  let f (vname, _) = (vname == name) in 
    let valueFound = find f vars in
       case valueFound of Just (name, id) -> name ++ (show id) 
                          Nothing -> name ++ (show 0)

uniquify_and_derive::Term->VarList->Int->(Term, Int)
uniquify_and_derive term vars lambdaId = 
  case term of Var var    -> (Var (getVarName var vars), lambdaId)
               Abs var type1 t2 -> 
                 let newLambdaId1 = lambdaId + 1 in 
                   let newVars = (var, lambdaId):vars in
                     let (uniqueBody, newLambdaId2) = uniquify_and_derive t2 newVars newLambdaId1 in 
                       (Abs (getVarName var newVars) type1 uniqueBody, newLambdaId2)
               App t1 t2 ->
                 let (uniqueT1, newLambdaId1) = uniquify_and_derive t1 vars lambdaId in
                   let (uniqueT2, newLambdaId2) = uniquify_and_derive t2 vars newLambdaId1 in
                     (App uniqueT1 uniqueT2, newLambdaId2)
               Seq t1 t2->
                 let (uniqueT1, newLambdaId1) = uniquify_and_derive t1 vars lambdaId in
                   let (uniqueT2, newLambdaId2) = uniquify_and_derive t2 vars newLambdaId1 in
                     let newLambdaId3 = newLambdaId2 + 1 in
                       (App (Abs ("x" ++ (show newLambdaId3)) TUnit uniqueT2) uniqueT1, newLambdaId3)                 
               t -> (t, lambdaId)
               
substitute::Variable->Term->Term->Term
substitute varName replaceTerm term = 
  case term of Var var          -> if var==varName then replaceTerm else term 
               Abs var type1 t2 -> Abs var type1 (substitute varName replaceTerm t2)
               App t1 t2        -> App (substitute varName replaceTerm t1) (substitute varName replaceTerm t2)
               t                -> t

eval::Term->Term
eval (App (Abs var type1 t1) t2) = 
  let t2_eval = eval t2 in
    if t2_eval == t2 
      then eval (substitute var t2_eval t1) 
      else eval (App (Abs var type1 t1) (eval t2))
eval (App t1 t2) = eval (App (eval t1) t2)
eval t = t

eval_to_value::Term->Value
eval_to_value t =
  let evaled_t = eval t in
    case evaled_t of (Abs var type1 term) -> Lambda (var, type1, term)
                     TrueT -> TrueValue
                     FalseT -> FalseValue
                     UnitT -> UnitValue
                     Var _ -> ErrorValue
                     term -> ValueTerm term

typeCheck::Term->Context->Type
typeCheck TrueT _  = TBool
typeCheck FalseT _ = TBool
typeCheck UnitT _ = TUnit
typeCheck (Var var) cxt = getVarType var cxt
typeCheck (Abs var type1 term) cxt = 
  let bodyType = typeCheck term ((var, type1):cxt) in
    TFun type1 bodyType
typeCheck (App t1 t2) ctx = 
  let t1_type = typeCheck t1 ctx in
    let t2_type = typeCheck t2 ctx in
      case t1_type of (TFun t1_type1 t1_type2) -> if t2_type == t1_type1 then t1_type2 else TUnknown
                      _                        -> TUnknown
  
prompt::(Show a, Read b, Show c, Read d) => (b->a) -> (d->c) -> IO()
prompt action action2 = do
  putStr "> "
  hFlush stdout
  input <- getLine
  if (input == "quit") then putStrLn "exiting..." else do 
    (putStrLn . show . action . read) input
    (putStrLn . show . action2 . read) input
    prompt action action2
    
main::IO()
main = 
  prompt ((\t -> typeCheck t [("unit", TUnit)]) . (\t -> let (term, _) = uniquify_and_derive t [] 0 in term)) (eval_to_value . (\t -> let (term, _) = uniquify_and_derive t [] 0 in term))   
