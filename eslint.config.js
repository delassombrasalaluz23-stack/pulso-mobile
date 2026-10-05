const {defineConfig}=require('eslint/config');
const expo=require('eslint-config-expo/flat');
module.exports=defineConfig([expo,{ignores:['supabase/functions/**','tests/**','dist/**']},{rules:{'react-hooks/exhaustive-deps':'off','@typescript-eslint/no-unused-vars':'off'}}]);
