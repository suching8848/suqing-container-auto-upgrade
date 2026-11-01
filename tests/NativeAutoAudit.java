import java.lang.reflect.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Real installed-game parser and input caches; no game or save initialization. */
public class NativeAutoAudit {
    static int assertions;
    static void check(boolean condition, String label) {
        assertions++;
        if (!condition) throw new AssertionError(label);
    }
    static Field field(Class<?> cls, String name) throws Exception {
        for (; cls != null; cls = cls.getSuperclass()) {
            try {Field f=cls.getDeclaredField(name); f.setAccessible(true); return f;}
            catch(NoSuchFieldException ignored) {}
        }
        throw new NoSuchFieldException(name);
    }
    public static void main(String[] args) throws Exception {
        Class<?> itemClass=Class.forName("zombie.scripting.objects.Item");
        Class<?> typeClass=Class.forName("zombie.scripting.objects.ItemType");
        Class<?> inputClass=Class.forName("zombie.scripting.entity.components.crafting.InputScript");
        Class<?> recipeClass=Class.forName("zombie.scripting.entity.components.crafting.CraftRecipe");
        Class<?> moduleClass=Class.forName("zombie.scripting.objects.ScriptModule");
        Class<?> parser=Class.forName("zombie.scripting.ScriptParser");
        check(typeClass.getField("CONTAINER").get(null)!=null,"actual CONTAINER registry constant");
        itemClass.getMethod("isItemType",typeClass);
        itemClass.getMethod("getClothingItemExtra");
        Class<?> inventoryClass=Class.forName("zombie.inventory.InventoryItem");
        inventoryClass.getMethod("getLuaCreate");
        Class.forName("zombie.inventory.types.InventoryContainer").getMethod("canBeEquipped");
        Object root=parser.getMethod("parse",String.class).invoke(null,new String(Files.readAllBytes(Paths.get(args[0])),StandardCharsets.UTF_8));
        Class<?> block=root.getClass(); int recipes=0;
        for (Object moduleBlock:(List<?>)block.getField("children").get(root)) {
            check("SuQingContainerUpgradeAuto".equals(block.getField("id").get(moduleBlock)),"independent recipe module");
            for (Object recipeBlock:(List<?>)block.getField("children").get(moduleBlock)) {
                if (!"craftRecipe".equals(block.getField("type").get(recipeBlock))) continue;
                recipes++;
                Object recipe=recipeClass.getConstructor().newInstance();
                Object module=moduleClass.getConstructor().newInstance();moduleClass.getField("name").set(module,"SuQingContainerUpgradeAuto");
                recipeClass.getMethod("setModule",moduleClass).invoke(recipe,module);
                String name=(String)block.getField("id").get(recipeBlock);
                field(recipeClass,"scriptObjectName").set(recipe,name);
                recipeClass.getMethod("Load",String.class,block).invoke(recipe,name,recipeBlock);
                List<?> inputs=(List<?>)recipeClass.getMethod("getInputs").invoke(recipe);
                Object target=inputs.get(0);boolean restore=name.endsWith("Restore");
                check((Boolean)inputClass.getMethod("isKeep").invoke(target),"target keeps original instance");
                check((Boolean)inputClass.getMethod("isItemCount").invoke(target),"target counts one item");
                check(!(Boolean)inputClass.getMethod("isAcceptsAnyItem").invoke(target),"no wildcard inputs");
                check(((Float)inputClass.getMethod("getAmount").invoke(target))==1f,"target amount unchanged");
                List<Object> ids=(List<Object>)inputClass.getMethod("getItems").invoke(target);
                List<Object> cache=(List<Object>)inputClass.getMethod("getPossibleInputItems").invoke(target);
                check(ids.size()==(restore?169:168),"original audited initial scope retained");
                Object item=itemClass.getConstructor().newInstance();
                Object itemModule=moduleClass.getConstructor().newInstance();moduleClass.getField("name").set(itemModule,"AutoProbe");
                itemClass.getMethod("setModule",moduleClass).invoke(item,itemModule);
                field(itemClass,"name").set(item,"StandardBag");
                field(itemClass,"moduleDotType").set(item,"AutoProbe.StandardBag");
                String fullName=(String)itemClass.getMethod("getFullName").invoke(item);
                check("AutoProbe.StandardBag".equals(fullName),"real script item full name");
                check(!(Boolean)inputClass.getMethod("containsItem",itemClass).invoke(target,item),"new script initially absent");
                ids.add(fullName);cache.add(item);
                check(ids.contains(fullName),"actual ID list mutable");
                check((Boolean)inputClass.getMethod("containsItem",itemClass).invoke(target,item),"actual native containsItem sees runtime addition");
                check((Boolean)inputClass.getMethod("canUseItem",String.class).invoke(target,fullName),"actual native canUseItem sees runtime addition");
                ids.remove(fullName);cache.remove(item);
                check(!(Boolean)inputClass.getMethod("containsItem",itemClass).invoke(target,item),"native cache rollback works");
                check(!ids.contains(fullName),"native ID rollback works");
            }
        }
        check(recipes==6,"five upgrade recipes plus one restore");
        System.out.println("AUTO_NATIVE assertions="+assertions+" failures=0");
    }
}
