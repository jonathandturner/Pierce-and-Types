module Main where

import System.IO
import Data.List

type Variable = String
type VarList = [(Variable, Int)]
type Context = [(Variable, Type)]  -- NOTE: I'm overloading the context to allow typevars for brevity, though this is not strictly correct

data Value = Lambda (Variable, Type, Term) | TypeLambda (Variable, Term) | TrueValue | FalseValue | ErrorValue | ValueTerm Term deriving Show
data Type = TFun Type Type | TVar Variable | TUniversal Variable Type | TBool | TAny | TUnknown deriving (Show, Read, Eq)
data Term = Var Variable | Abs Variable Type Term | App Term Term | TypeAbs Variable Term | TypeApp Term Type | TrueT | FalseT deriving (Show, Read, Eq)

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
                          Nothing -> name

uniquify::Term->VarList->Int->(Term, Int)
uniquify term vars lambdaId = 
  case term of Var var    -> (Var (getVarName var vars), lambdaId)
               Abs var type1 t2 -> 
                 let newLambdaId1 = lambdaId + 1 in 
                   let newVars = (var, lambdaId):vars in
                     let (uniqueBody, newLambdaId2) = uniquify t2 newVars newLambdaId1 in 
                       (Abs (getVarName var newVars) type1 uniqueBody, newLambdaId2)
               App t1 t2 ->
                 let (uniqueT1, newLambdaId1) = uniquify t1 vars lambdaId in
                   let (uniqueT2, newLambdaId2) = uniquify t2 vars newLambdaId1 in
                     (App uniqueT1 uniqueT2, newLambdaId2)
               t -> (t, lambdaId)
               
substitute::Variable->Term->Term->Term
substitute varName replaceTerm term = 
  case term of Var var          -> if var==varName then replaceTerm else term 
               Abs var type1 t2 -> Abs var type1 (substitute varName replaceTerm t2)
               App t1 t2        -> App (substitute varName replaceTerm t1) (substitute varName replaceTerm t2)

substituteTypeInType::Variable->Type->Type->Type
substituteTypeInType varName replaceType type1 =
  case type1 of TVar var          -> if var == varName then replaceType else type1
                TFun t1 t2        -> TFun (substituteTypeInType varName replaceType t1) (substituteTypeInType varName replaceType t2)
                TUniversal vn1 t1 -> TUniversal vn1 (substituteTypeInType varName replaceType t1) -- is this correct?
                 
substituteType::Variable->Type->Term->Term
substituteType varName replaceType term = 
  case term of Var var          -> term 
               Abs var type1 t2 -> Abs var (substituteTypeInType var replaceType type1) (substituteType varName replaceType t2)
               App t1 t2        -> App (substituteType varName replaceType t1) (substituteType varName replaceType t2)
               TypeAbs var t1   -> TypeAbs var (substituteType varName replaceType t1)
               TypeApp t1 type1 -> TypeApp (substituteType varName replaceType t1) (substituteTypeInType varName replaceType type1)
               
eval::Term->Term
eval (App (Abs var type1 t1) t2) = 
  let t2_eval = eval t2 in
    if t2_eval == t2 
      then eval (substitute var (eval t2) t1) 
      else eval (App (Abs var type1 t1) (eval t2))
eval (App t1 t2) = eval (App (eval t1) t2)
eval (TypeApp (TypeAbs var t1) type1) = 
  eval (substituteType var type1 t1)
eval (TypeApp t1 type1) = 
  eval (TypeApp (eval t1) type1)      
eval t = t

eval_to_value::Term->Value
eval_to_value t =
  let evaled_t = eval t in
    case evaled_t of (Abs var type1 term) -> Lambda (var, type1, term)
                     (TypeAbs var term) -> TypeLambda (var, term)
                     TrueT -> TrueValue
                     FalseT -> FalseValue
                     Var _ -> ErrorValue
                     term -> ValueTerm term

typeCheck::Term->Context->Type
typeCheck TrueT _  = TBool
typeCheck FalseT _ = TBool
typeCheck (Var var) ctx = getVarType var ctx
typeCheck (Abs var type1 term) ctx = 
  let bodyType = typeCheck term ((var, type1):ctx) in
    TFun type1 bodyType
typeCheck (App t1 t2) ctx = 
  let t1_type = typeCheck t1 ctx in
    let t2_type = typeCheck t2 ctx in
      case t1_type of (TFun t1_type1 t1_type2) -> if t2_type == t1_type1 then t1_type2 else TUnknown
                      _                        -> TUnknown
typeCheck (TypeAbs var term) ctx =
  let bodyType = typeCheck term ((var, TAny):ctx) in
    TUniversal var bodyType
typeCheck (TypeApp t1 type1) ctx = 
  let t1_type = typeCheck t1 ctx in
    case t1_type of (TUniversal tvar bodyType) -> substituteTypeInType tvar type1 bodyType
                    _                          -> TUnknown
                    
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
  prompt ((\t -> typeCheck t []) . (\t -> let (term, _) = uniquify t [] 0 in term)) (eval_to_value . (\t -> let (term, _) = uniquify t [] 0 in term))   
