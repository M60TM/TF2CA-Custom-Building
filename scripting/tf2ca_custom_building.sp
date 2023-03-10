#pragma semicolon 1
#include <sourcemod>
#include <dhooks>
#include <sdkhooks>
#include <sdktools>
#include <tf2_stocks>

#pragma newdecls required

#include <tf2utils>
#include <tf_custom_attributes>
#include <stocksoup/functions>
#include <stocksoup/tf/entity_prop_stocks>
#include <stocksoup/var_strings>

/////////////////////////////
// PLUGIN INFO             //
/////////////////////////////

public Plugin myinfo = {
	name = "[TF2] Custom Attribute: Custom Building",
	author = "Sandy and Monera",
	description = "A few native and custom attributes, forwards for handling custom building.",
	version = "1.2.0",
	url = "https://github.com/M60TM/TF2CA-Custom-Building"
}

/////////////////////////////
// Forward                 //
/////////////////////////////

Handle g_OnBuildObjectForward;
Handle g_OnUpgradeObjectForward;
Handle g_OnCarryObjectForward;
Handle g_OnDropObjectForward;
Handle g_OnObjectRemovedForward;
Handle g_OnObjectDestroyedForward;
Handle g_OnObjectDetonatedForward;
Handle g_ObjectOnGoActiveForward;
Handle g_DispenserStartHealingForward;
Handle g_DispenserStopHealingForward;

/////////////////////////////
// SDKCall                 //
/////////////////////////////

Handle g_SDKCallDetonateObjectOfType;
Handle g_SDKCallBuildingDestroyScreens;
Handle g_SDKCallPlayerGetObjectOfType;

/////////////////////////////
// DHooks                  //
/////////////////////////////

Handle g_DHookObjectOnGoActive;
Handle g_DHookDispenserStartHealing;
Handle g_DHookObjectGetMaxHealth;
Handle g_DHookSentrySetModel;
Handle g_DHookDispenserSetModel;
Handle g_DHookTeleporterSetModel;
Handle g_DHookGetHealRate;

char g_sCustomBuildingType[MAXPLAYERS + 1][3][64];

StringMap g_MissingModels;

public APLRes AskPluginLoad2(Handle self, bool late, char[] error, int maxlen) {
    RegPluginLibrary("tf2ca_custom_building");
    
    CreateNative("TF2CA_BuilderHasCustomDispenser", Native_BuilderHasCustomDispenser);
    CreateNative("TF2CA_BuilderHasCustomSentry", Native_BuilderHasCustomSentry);
    CreateNative("TF2CA_BuilderHasCustomTeleporter", Native_BuilderHasCustomTeleporter);
    CreateNative("TF2CA_DetonateObjectOfType", Native_DetonateObjectOfType);
    CreateNative("TF2CA_PlayerGetObjectOfType", Native_PlayerGetObjectOfType);
    CreateNative("TF2CA_DestroyScreens", Native_DestroyScreens);

    return APLRes_Success;
}

public void OnPluginStart() 
{
    Handle hGameConf = LoadGameConfigFile("tf2.cattr_object");
    if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.cattr_object).");
	}
    
    StartPrepSDKCall(SDKCall_Player);
    PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CTFPlayer::DetonateObjectOfType()");
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //int - type
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //int - mode
    PrepSDKCall_AddParameter( SDKType_PlainOldData, SDKPass_Plain ); //bool - silent
    g_SDKCallDetonateObjectOfType = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Player);
    PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CTFPlayer::GetObjectOfType()");
    PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    g_SDKCallPlayerGetObjectOfType = EndPrepSDKCall();
    
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature, "CBaseObject::DestroyScreens()");
    g_SDKCallBuildingDestroyScreens = EndPrepSDKCall();
    
    g_DHookObjectOnGoActive = DHookCreateFromConf(hGameConf, "CBaseObject::OnGoActive()");
    g_DHookDispenserStartHealing = DHookCreateFromConf(hGameConf, "CObjectDispenser::StartHealing()");

    g_DHookObjectGetMaxHealth = DHookCreateFromConf(hGameConf, "CBaseObject::GetMaxHealthForCurrentLevel()");

    g_DHookSentrySetModel = DHookCreateFromConf(hGameConf, "CObjectSentrygun::SetModel()");
    g_DHookDispenserSetModel = DHookCreateFromConf(hGameConf, "CObjectDispenser::SetModel()");
    g_DHookTeleporterSetModel = DHookCreateFromConf(hGameConf, "CObjectTeleporter::SetModel()");

    g_DHookGetHealRate = DHookCreateFromConf(hGameConf, "CObjectDispenser::GetHealRate()");

    Handle DHookCalculateObjectCost = DHookCreateFromConf(hGameConf, "CTFPlayerShared::CalculateObjectCost()");
    DHookEnableDetour(DHookCalculateObjectCost, true, OnCalculateObjectCostPost);

    Handle DHookDispenserStopHealing = DHookCreateFromConf(hGameConf, "CObjectDispenser::StopHealing()");
    DHookEnableDetour(DHookDispenserStopHealing, true, OnDispenserStopHealingPost);

    Handle DHookGetConstructionMultiplier = DHookCreateFromConf(hGameConf, "CBaseObject::GetConstructionMultiplier()");
    DHookEnableDetour(DHookGetConstructionMultiplier, true, GetConstructionMultiplierPost);

    delete hGameConf;

    g_OnBuildObjectForward = CreateGlobalForward("TF2CA_OnBuildObject", ET_Event, Param_Cell,
			Param_Cell, Param_Cell);
    
    g_OnUpgradeObjectForward = CreateGlobalForward("TF2CA_OnUpgradeObject", ET_Event, Param_Cell,
			Param_Cell, Param_Cell, Param_Cell);

    g_OnCarryObjectForward = CreateGlobalForward("TF2CA_OnCarryObject", ET_Event, Param_Cell,
			Param_Cell, Param_Cell);

    g_OnDropObjectForward = CreateGlobalForward("TF2CA_OnDropObject", ET_Event, Param_Cell,
			Param_Cell, Param_Cell);

    g_OnObjectRemovedForward = CreateGlobalForward("TF2CA_OnObjectRemoved", ET_Event, Param_Cell,
			Param_Cell, Param_Cell);

    g_OnObjectDestroyedForward = CreateGlobalForward("TF2CA_OnObjectDestroyed", ET_Event, Param_Cell,
			Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

    g_OnObjectDetonatedForward = CreateGlobalForward("TF2CA_OnObjectDetonated", ET_Event, Param_Cell,
			Param_Cell, Param_Cell);

    g_ObjectOnGoActiveForward = CreateGlobalForward("TF2CA_ObjectOnGoActive", ET_Event, Param_Cell,
			Param_Cell, Param_Cell);

    g_DispenserStartHealingForward = CreateGlobalForward("TF2CA_DispenserStartHealing", ET_Event, Param_Cell,
			Param_Cell, Param_Cell);

    g_DispenserStopHealingForward = CreateGlobalForward("TF2CA_DispenserStopHealing", ET_Event, Param_Cell,
			Param_Cell, Param_Cell);
}

public void OnMapStart()
{
    HookEvent("post_inventory_application", OnInventoryAppliedPost);
    HookEvent("player_builtobject", OnBuildObject);
    HookEvent("player_upgradedobject", OnUpgradeObject);
    HookEvent("player_carryobject", OnCarryObject);
    HookEvent("player_dropobject", OnDropObject);
    HookEvent("object_removed", OnObjectRemoved);
    HookEvent("object_destroyed", OnObjectDestroyed);
    HookEvent("object_detonated", OnObjectDetonated);
    
    delete g_MissingModels;
    g_MissingModels = new StringMap();
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if(StrEqual(classname, "obj_sentrygun"))
    {
        DHookEntity(g_DHookSentrySetModel, false, entity, .callback = SentrySetModelPre);
        DHookEntity(g_DHookObjectGetMaxHealth, true, entity, .callback = ObjectGetMaxHealthPost);
    }
    else if(StrEqual(classname, "obj_dispenser"))
    {
        DHookEntity(g_DHookDispenserSetModel, false, entity, .callback = DispenserSetModelPre);
        DHookEntity(g_DHookObjectGetMaxHealth, true, entity, .callback = ObjectGetMaxHealthPost);
        DHookEntity(g_DHookGetHealRate, true, entity, .callback = DispenserGetHealRatePost);
    }
    else if(StrEqual(classname, "obj_teleporter"))
    {
        DHookEntity(g_DHookTeleporterSetModel, false, entity, .callback = TeleporterSetModelPre);
        DHookEntity(g_DHookObjectGetMaxHealth, true, entity, .callback = ObjectGetMaxHealthPost);
    }
    else if(StrEqual(classname, "tf_projectile_sentryrocket"))
    {
        SDKHook(entity, SDKHook_SpawnPost, SentryRocketSpawnPost);
    }
}

void SentryRocketSpawnPost(int rocket)
{
    int owner = GetEntPropEnt(rocket, Prop_Data, "m_hOwnerEntity");

    int builder = GetEntPropEnt(owner, Prop_Send, "m_hBuilder");

    if (IsValidClient(builder))
	{
		char sAttributes[256];
		if(TF2CustAttr_ClientHasString(builder, "custom sentry rocket model", sAttributes, sizeof(sAttributes)))
		{
			SetSentryRocketModel(rocket, sAttributes);
		}
	}
    
    return;
}

/////////////////////////////
// Events                  //
/////////////////////////////

void OnInventoryAppliedPost(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    
    if (!IsValidClient(client))
    {
        return;
    }
    if (TF2_GetPlayerClass(client) != TFClass_Engineer)
    {
        return;
    }

    char attr[3][64];
    for(int i = 0; i < 3; i++)
    {
        attr[i][0] = '\0';
    }

    for(int i = 0; i < 5; i++)
    {
        int weapon = GetPlayerWeaponSlot(client, i);

        if(!IsValidEntity(weapon))
        {
            continue;
        }

        TF2CustAttr_GetString(weapon, "custom dispenser type", attr[0], sizeof(attr[]), attr[0]);
        TF2CustAttr_GetString(weapon, "custom sentry type", attr[1], sizeof(attr[]), attr[1]);
        TF2CustAttr_GetString(weapon, "custom teleporter type", attr[2], sizeof(attr[]), attr[2]);
    }
    
    int buildings = TF2Util_GetPlayerObjectCount(client);
    
    for(int i = 0; i < buildings ; i++)
	{
        int building = TF2Util_GetPlayerObject(client, i);
        if (!IsValidEntity(building))
        {
            continue;
        }

        TFObjectType type = TF2_GetObjectType(building);
        switch(type)
        {
            case TFObject_Dispenser:
            {
                if(strcmp(attr[0], g_sCustomBuildingType[client][0]) != 0)
                {
                    DetonateObjectOfType(client, 0, 0, true);
                }
            }
            case TFObject_Sentry:
            {
                if(strcmp(attr[1], g_sCustomBuildingType[client][1]) != 0)
                {
                    DetonateObjectOfType(client, 2, 0, true);
                }
            }
            case TFObject_Teleporter:
            {
                if(strcmp(attr[2], g_sCustomBuildingType[client][2]) != 0)
                {
                    DetonateObjectOfType(client, 1, 0, true);
                    DetonateObjectOfType(client, 1, 1, true);
                }
            }
        }
	}
    
    for(int i = 0; i < 3; i++)
    {
        strcopy(g_sCustomBuildingType[client][i], sizeof(g_sCustomBuildingType[][]), attr[i]);
    }
}

/**
 * forward void TF2CA_OnBuildObject(int builder, int building, TFObjectType buildingtype)
 */
void OnBuildObject(Event event, const char[] name, bool dontBroadcast)
{
    int builder = GetClientOfUserId(event.GetInt("userid"));

    if (!IsValidClient(builder))
    {
        builder = -1;
    }

    int building = event.GetInt("index");

    TFObjectType buildingtype = TF2_GetObjectType(building);
    
    Call_StartForward(g_OnBuildObjectForward);
    Call_PushCell(builder);
    Call_PushCell(building);
    Call_PushCell(buildingtype);
    Call_Finish();

    SetupObjectDHooks(building, buildingtype);

    if (builder != -1)
    {
        int wrench = GetPlayerWeaponSlot(builder, 2);
        char attr[256];
        if(TF2CustAttr_GetString(wrench, "building upgrade cost", attr, sizeof(attr)))
        {
            UpdateBuildingInfo(building, buildingtype, attr);
        }
    }
}

void SetupObjectDHooks(int building, TFObjectType type)
{
    DHookEntity(g_DHookObjectOnGoActive, true, building, .callback = ObjectOnGoActivePost);

    if (type == TFObject_Dispenser)
    {
        DHookEntity(g_DHookDispenserStartHealing, true, building, .callback = DispenserStartHealingPost);
    }
}

/**
 * forward void TF2CA_OnBuildObject(int builder, int building, TFObjectType buildingtype)
 */
void OnUpgradeObject(Event event, const char[] name, bool dontBroadcast)
{
    int upgrader = GetClientOfUserId(event.GetInt("userid"));

    if (!IsValidClient(upgrader))
    {
        upgrader = -1;
    }

    int building = event.GetInt("index");

    int builder = TF2_GetObjectBuilder(building);

    if (!IsValidClient(builder))
    {
        builder = -1;
    }

    TFObjectType buildingtype = TF2_GetObjectType(building);
    
    Call_StartForward(g_OnUpgradeObjectForward);
    Call_PushCell(upgrader);
    Call_PushCell(builder);
    Call_PushCell(building);
    Call_PushCell(buildingtype);
    Call_Finish();

    if (builder != -1)
    {
        int wrench = GetPlayerWeaponSlot(builder, 2);
        char attr[256];
        if(TF2CustAttr_GetString(wrench, "building upgrade cost", attr, sizeof(attr)))
        {
            UpdateBuildingInfo(building, buildingtype, attr);
        }
    }
}

/**
 * forward void TF2CA_OnCarryObject(int builder, int building, TFObjectType buildingtype);
 */
void OnCarryObject(Event event, const char[] name, bool dontBroadcast)
{
    int builder = GetClientOfUserId(event.GetInt("userid"));

    if (!IsValidClient(builder))
    {
        builder = -1;
    }

    int building = event.GetInt("index");

    TFObjectType buildingtype = TF2_GetObjectType(building);
    
    Call_StartForward(g_OnCarryObjectForward);
    Call_PushCell(builder);
    Call_PushCell(building);
    Call_PushCell(buildingtype);
    Call_Finish();
}

/**
 * forward void TF2CA_OnDropObject(int builder, int building, TFObjectType buildingtype);
 */
void OnDropObject(Event event, const char[] name, bool dontBroadcast)
{
    int builder = GetClientOfUserId(event.GetInt("userid"));

    if (!IsValidClient(builder))
    {
        builder = -1;
    }

    int building = event.GetInt("index");

    TFObjectType buildingtype = TF2_GetObjectType(building);
    
    Call_StartForward(g_OnDropObjectForward);
    Call_PushCell(builder);
    Call_PushCell(building);
    Call_PushCell(buildingtype);
    Call_Finish();
}

/**
 * forward void TF2CA_OnObjectRemoved(int builder, int building, TFObjectType buildingtype)
 */
void OnObjectRemoved(Event event, const char[] name, bool dontBroadcast)
{
    int builder = GetClientOfUserId(event.GetInt("userid"));

    if (!IsValidClient(builder))
    {
        builder = -1;
    }

    int building = event.GetInt("index");

    TFObjectType buildingtype = TF2_GetObjectType(building);

    Call_StartForward(g_OnObjectRemovedForward);
    Call_PushCell(builder);
    Call_PushCell(building);
    Call_PushCell(buildingtype);
    Call_Finish();
}

/**
 * forward void TF2CA_OnObjectRemoved(int builder, int building, TFObjectType buildingtype)
 */
void OnObjectDestroyed(Event event, const char[] name, bool dontBroadcast)
{
    int builder = GetClientOfUserId(event.GetInt("userid"));

    if (!IsValidClient(builder))
    {
        builder = -1;
    }

    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (!IsValidClient(attacker))
    {
        attacker = -1;
    }

    int assister = GetClientOfUserId(event.GetInt("assister"));

    if (!IsValidClient(assister))
    {
        assister = -1;
    }

    int weapon = event.GetInt("weaponid");

    if (!IsValidEntity(weapon))
    {
        weapon = -1;
    }

    int building = event.GetInt("index");

    bool wasbuilding = event.GetBool("was_building");

    TFObjectType buildingtype = TF2_GetObjectType(building);

    Call_StartForward(g_OnObjectDestroyedForward);
    Call_PushCell(builder);
    Call_PushCell(attacker);
    Call_PushCell(assister);
    Call_PushCell(weapon);
    Call_PushCell(building);
    Call_PushCell(buildingtype);
    Call_PushCell(wasbuilding);
    Call_Finish();
}

/**
 * forward void TF2CA_OnObjectDetonated(int builder, int building, TFObjectType buildingtype);
 */
void OnObjectDetonated(Event event, const char[] name, bool dontBroadcast)
{
    int builder = GetClientOfUserId(event.GetInt("userid"));

    if (!IsValidClient(builder))
    {
        builder = -1;
    }

    int building = event.GetInt("index");

    TFObjectType buildingtype = TF2_GetObjectType(building);

    Call_StartForward(g_OnObjectDetonatedForward);
    Call_PushCell(builder);
    Call_PushCell(building);
    Call_PushCell(buildingtype);
    Call_Finish();
}

/////////////////////////////
// DHooks                  //
/////////////////////////////

/**
 * forward void TF2CA_ObjectOnGoActive(int builder, int building, TFObjectType buildingtype);
 */
MRESReturn ObjectOnGoActivePost(int building)
{
    int builder = TF2_GetObjectBuilder(building);
    
    TFObjectType buildingtype = TF2_GetObjectType(building);
    
    Call_StartForward(g_ObjectOnGoActiveForward);
    Call_PushCell(builder);
    Call_PushCell(building);
    Call_PushCell(buildingtype);
    Call_Finish();

    return MRES_Ignored;
}

/**
 * forward void TF2CA_DispenserStartHealing(int builder, int building, int patient);
 */
MRESReturn DispenserStartHealingPost(int building, Handle hParams)
{
    int builder = TF2_GetObjectBuilder(building);

    if (!IsValidClient(builder))
    {
        builder = -1;
    }

    int patient = DHookGetParam(hParams, 1);
    
    if (!IsValidClient(patient))
    {
        patient = -1;
    }
    
    Call_StartForward(g_DispenserStartHealingForward);
    Call_PushCell(builder);
    Call_PushCell(building);
    Call_PushCell(patient);
    Call_Finish();

    return MRES_Ignored;
}

/**
 * forward void TF2CA_DispenserStopHealing(int builder, int building, int patient);
 */
MRESReturn OnDispenserStopHealingPost(int building, DHookParam hParams)
{
    int builder = TF2_GetObjectBuilder(building);

    if (!IsValidClient(builder))
    {
        builder = -1;
    }

    int patient = DHookGetParam(hParams, 1);

    if (!IsValidClient(patient))
    {
        patient = -1;
    }

    Call_StartForward(g_DispenserStopHealingForward);
    Call_PushCell(builder);
    Call_PushCell(building);
    Call_PushCell(patient);
    Call_Finish();

    return MRES_Ignored;
}

MRESReturn GetConstructionMultiplierPost(int building, DHookReturn hReturn)
{
    int builder = TF2_GetObjectBuilder(building);
    if (!IsValidClient(builder))
    {
        return MRES_Ignored;
    }

    if (TF2_GetObjectType(building) == TFObject_Dispenser)
    {
        float returnvalue = DHookGetReturn(hReturn);
        returnvalue = TF2CustAttr_HookValueFloatOnClient(returnvalue, "engineer dispenser build rate multiplier", builder);
        DHookSetReturn(hReturn, returnvalue);

        return MRES_Override;
    }

    return MRES_Ignored;
}

MRESReturn ObjectGetMaxHealthPost(int building, DHookReturn hReturn)
{
    int builder = TF2_GetObjectBuilder(building);
    if (!IsValidClient(builder))
    {
        return MRES_Ignored;
    }

    int wrench = GetPlayerWeaponSlot(builder, 2);
    int level = GetEntProp(building, Prop_Send, "m_iUpgradeLevel");
    
    if(IsValidEntity(wrench)) {
        char attr[512];
        if(TF2CustAttr_GetString(wrench, "override building health", attr, sizeof(attr)))
        {
            TFObjectType BuildingType = TF2_GetObjectType(building);
            switch(BuildingType) {
                case TFObject_Sentry: {
                    if (ReadIntVar(attr, "sentry"))
                    {
                        switch(level) {
                            case 1:
                            {
                                DHookSetReturn(hReturn, ReadIntVar(attr, "sentry1", 150));
                                return MRES_ChangedOverride;
                            }
                            case 2:
                            {
                                DHookSetReturn(hReturn, ReadIntVar(attr, "sentry2", 180));
                                return MRES_ChangedOverride;
                            }
                            case 3:
                            {
                                DHookSetReturn(hReturn, ReadIntVar(attr, "sentry3", 216));
                                return MRES_ChangedOverride;
                            }
                        }
                    }
                }
                case TFObject_Dispenser: {
                    if (ReadIntVar(attr, "dispenser"))
                    {
                        switch(level) {
                            case 1:
                            {
                                DHookSetReturn(hReturn, ReadIntVar(attr, "dispenser1", 150));
                                return MRES_ChangedOverride;
                            }
                            case 2:
                            {
                                DHookSetReturn(hReturn, ReadIntVar(attr, "dispenser2", 180));
                                return MRES_ChangedOverride;
                            }
                            case 3:
                            {
                                DHookSetReturn(hReturn, ReadIntVar(attr, "dispenser3", 216));
                                return MRES_ChangedOverride;
                            }
                        }
                    }
                }
                case TFObject_Teleporter: {
                    if (ReadIntVar(attr, "teleporter"))
                    {
                        switch(level) {
                            case 1:
                            {
                                DHookSetReturn(hReturn, ReadIntVar(attr, "teleporter1", 150));
                                return MRES_ChangedOverride;
                            }
                            case 2:
                            {
                                DHookSetReturn(hReturn, ReadIntVar(attr, "teleporter2", 180));
                                return MRES_ChangedOverride;
                            }
                            case 3:
                            {
                                DHookSetReturn(hReturn, ReadIntVar(attr, "teleporter3", 216));
                                return MRES_ChangedOverride;
                            }
                        }
                    }
                }
            }
        }
	}
    
    return MRES_Ignored;
}

MRESReturn DispenserGetHealRatePost(int building, DHookReturn hReturn)
{
    int builder = TF2_GetObjectBuilder(building);
    if (!IsValidClient(builder))
    {
        return MRES_Ignored;
    }

    float healrate = DHookGetReturn(hReturn);
    healrate = TF2CustAttr_HookValueFloatOnClient(healrate, "dispenser healrate multiplier", builder);
    DHookSetReturn(hReturn, healrate);
    return MRES_Override;
}

#define SENTRY_BLUEPRINT_MODEL  "models/buildables/sentry1_blueprint.mdl"
#define SENTRY_LV1_MODEL        "models/buildables/sentry1.mdl"
#define SENTRY_LV1_HEAVY_MODEL        "models/buildables/sentry1_heavy.mdl"
#define SENTRY_LV2_MODEL        "models/buildables/sentry2.mdl"
#define SENTRY_LV2_HEAVY_MODEL        "models/buildables/sentry2_heavy.mdl"
#define SENTRY_LV3_MODEL        "models/buildables/sentry3.mdl"
#define SENTRY_LV3_HEAVY_MODEL        "models/buildables/sentry3_heavy.mdl"

MRESReturn SentrySetModelPre(int building, DHookParam hParams)
{
    int builder = TF2_GetObjectBuilder(building);

    if (!IsValidClient(builder))
    {
        return MRES_Ignored;
    }

    char newsentrymodel[128];
    if (!TF2CustAttr_ClientHasString(builder, "custom sentry model", newsentrymodel, sizeof(newsentrymodel)))
    {
        return MRES_Ignored;
    }

    char oldsentrymodel[PLATFORM_MAX_PATH];
    DHookGetParamString(hParams, 1, oldsentrymodel, sizeof(oldsentrymodel));
    if(StrEqual(oldsentrymodel, SENTRY_BLUEPRINT_MODEL))
    {
        StrCat(newsentrymodel, PLATFORM_MAX_PATH, "1_blueprint.mdl");
        if (FileExists(newsentrymodel, true))
        {
            PrecacheModelAndLog(newsentrymodel);
            DHookSetParamString(hParams, 1, newsentrymodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(oldsentrymodel, SENTRY_LV1_MODEL))
    {
        StrCat(newsentrymodel, PLATFORM_MAX_PATH, "1.mdl");
        if (FileExistsAndLog(newsentrymodel, true))
        {
            PrecacheModelAndLog(newsentrymodel);
            DHookSetParamString(hParams, 1, newsentrymodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(oldsentrymodel, SENTRY_LV1_HEAVY_MODEL))
    {
        StrCat(newsentrymodel, PLATFORM_MAX_PATH, "1_heavy.mdl");
        if (FileExistsAndLog(newsentrymodel, true))
        {
            PrecacheModelAndLog(newsentrymodel);
            DHookSetParamString(hParams, 1, newsentrymodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(oldsentrymodel, SENTRY_LV2_MODEL))
    {
        StrCat(newsentrymodel, PLATFORM_MAX_PATH, "2.mdl");
        if (FileExistsAndLog(newsentrymodel, true))
        {
            PrecacheModelAndLog(newsentrymodel);
            DHookSetParamString(hParams, 1, newsentrymodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(oldsentrymodel, SENTRY_LV2_HEAVY_MODEL))
    {
        StrCat(newsentrymodel, PLATFORM_MAX_PATH, "2_heavy.mdl");
        if (FileExistsAndLog(newsentrymodel, true))
        {
            PrecacheModelAndLog(newsentrymodel);
            DHookSetParamString(hParams, 1, newsentrymodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(oldsentrymodel, SENTRY_LV3_MODEL))
    {
        StrCat(newsentrymodel, PLATFORM_MAX_PATH, "3.mdl");
        if (FileExistsAndLog(newsentrymodel, true))
        {
            PrecacheModelAndLog(newsentrymodel);
            DHookSetParamString(hParams, 1, newsentrymodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(oldsentrymodel, SENTRY_LV3_HEAVY_MODEL))
    {
        StrCat(newsentrymodel, PLATFORM_MAX_PATH, "3_heavy.mdl");
        if (FileExistsAndLog(newsentrymodel, true))
        {
            PrecacheModelAndLog(newsentrymodel);
            DHookSetParamString(hParams, 1, newsentrymodel);

            return MRES_ChangedHandled;
        }
    }

    return MRES_Ignored;
}

#define DISPENSER_BLUEPRINT_MODEL  "models/buildables/dispenser_blueprint.mdl"
#define DISPENSER_LV1_LIGHT_MODEL        "models/buildables/dispenser_light.mdl"
#define DISPENSER_LV1_MODEL        "models/buildables/dispenser.mdl"
#define DISPENSER_LV2_LIGHT_MODEL        "models/buildables/dispenser_lvl2_light.mdl"
#define DISPENSER_LV2_MODEL        "models/buildables/dispenser_lvl2.mdl"
#define DISPENSER_LV3_LIGHT_MODEL        "models/buildables/dispenser_lvl3_light.mdl"
#define DISPENSER_LV3_MODEL        "models/buildables/dispenser_lvl3.mdl"

MRESReturn DispenserSetModelPre(int building, DHookParam hParams)
{
    int builder = TF2_GetObjectBuilder(building);

    if (!IsValidClient(builder))
    {
        return MRES_Ignored;
    }

    char newdispensermodel[128];
    if (!TF2CustAttr_ClientHasString(builder, "custom dispenser model", newdispensermodel, sizeof(newdispensermodel)))
    {
        return MRES_Ignored;
    }

    char olddispensermodel[PLATFORM_MAX_PATH];
    DHookGetParamString(hParams, 1, olddispensermodel, sizeof(olddispensermodel));
    if(StrEqual(olddispensermodel, DISPENSER_BLUEPRINT_MODEL))
    {
        StrCat(newdispensermodel, PLATFORM_MAX_PATH, "_blueprint.mdl");
        if (FileExists(newdispensermodel, true))
        {
            PrecacheModelAndLog(newdispensermodel);
            DHookSetParamString(hParams, 1, newdispensermodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(olddispensermodel, DISPENSER_LV1_LIGHT_MODEL))
    {
        StrCat(newdispensermodel, PLATFORM_MAX_PATH, "_light.mdl");
        if (FileExistsAndLog(newdispensermodel, true))
        {
            PrecacheModelAndLog(newdispensermodel);
            DHookSetParamString(hParams, 1, newdispensermodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(olddispensermodel, DISPENSER_LV1_MODEL))
    {
        StrCat(newdispensermodel, PLATFORM_MAX_PATH, ".mdl");
        if (FileExists(newdispensermodel, true))
        {
            PrecacheModelAndLog(newdispensermodel);
            DHookSetParamString(hParams, 1, newdispensermodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(olddispensermodel, DISPENSER_LV2_LIGHT_MODEL))
    {
        StrCat(newdispensermodel, PLATFORM_MAX_PATH, "_lvl2_light.mdl");
        if (FileExists(newdispensermodel, true))
        {
            PrecacheModelAndLog(newdispensermodel);
            DHookSetParamString(hParams, 1, newdispensermodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(olddispensermodel, DISPENSER_LV2_MODEL))
    {
        StrCat(newdispensermodel, PLATFORM_MAX_PATH, "_lvl2.mdl");
        if (FileExists(newdispensermodel, true))
        {
            PrecacheModelAndLog(newdispensermodel);
            DHookSetParamString(hParams, 1, newdispensermodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(olddispensermodel, DISPENSER_LV3_LIGHT_MODEL))
    {
        StrCat(newdispensermodel, PLATFORM_MAX_PATH, "_lvl3_light.mdl");
        if (FileExists(newdispensermodel, true))
        {
            PrecacheModelAndLog(newdispensermodel);
            DHookSetParamString(hParams, 1, newdispensermodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(olddispensermodel, DISPENSER_LV3_MODEL))
    {
        StrCat(newdispensermodel, PLATFORM_MAX_PATH, "_lvl3.mdl");
        if (FileExists(newdispensermodel, true))
        {
            PrecacheModelAndLog(newdispensermodel);
            DHookSetParamString(hParams, 1, newdispensermodel);

            return MRES_ChangedHandled;
        }
    }

    return MRES_Ignored;
}

#define TELEPORTER_BLUEPRINT_ENTER_MODEL  "models/buildables/teleporter_blueprint_enter.mdl"
#define TELEPORTER_BLUEPRINT_EXIT_MODEL        "models/buildables/teleporter_blueprint_exit.mdl"
#define TELEPORTER_LIGHT_MODEL        "models/buildables/teleporter_light.mdl"
#define TELEPORTER_MODEL        "models/buildables/teleporter.mdl"

MRESReturn TeleporterSetModelPre(int building, DHookParam hParams)
{
    int builder = TF2_GetObjectBuilder(building);

    if (!IsValidClient(builder))
    {
        return MRES_Ignored;
    }

    char newteleportermodel[128];
    if (!TF2CustAttr_ClientHasString(builder, "custom teleporter model", newteleportermodel, sizeof(newteleportermodel)))
    {
        return MRES_Ignored;
    }

    char oldteleportermodel[PLATFORM_MAX_PATH];
    DHookGetParamString(hParams, 1, oldteleportermodel, sizeof(oldteleportermodel));
    if(StrEqual(oldteleportermodel, TELEPORTER_BLUEPRINT_ENTER_MODEL))
    {
        StrCat(newteleportermodel, PLATFORM_MAX_PATH, "_blueprint_enter.mdl");
        if (FileExists(newteleportermodel, true))
        {
            PrecacheModelAndLog(newteleportermodel);
            DHookSetParamString(hParams, 1, newteleportermodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(oldteleportermodel, TELEPORTER_BLUEPRINT_EXIT_MODEL))
    {
        StrCat(newteleportermodel, PLATFORM_MAX_PATH, "_blueprint_exit.mdl");
        if (FileExists(newteleportermodel, true))
        {
            PrecacheModelAndLog(newteleportermodel);
            DHookSetParamString(hParams, 1, newteleportermodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(oldteleportermodel, TELEPORTER_LIGHT_MODEL))
    {
        StrCat(newteleportermodel, PLATFORM_MAX_PATH, "_light.mdl");
        if (FileExists(newteleportermodel, true))
        {
            PrecacheModelAndLog(newteleportermodel);
            DHookSetParamString(hParams, 1, newteleportermodel);

            return MRES_ChangedHandled;
        }
    }
    else if(StrEqual(oldteleportermodel, TELEPORTER_MODEL))
    {
        StrCat(newteleportermodel, PLATFORM_MAX_PATH, ".mdl");
        if (FileExists(newteleportermodel, true))
        {
            PrecacheModelAndLog(newteleportermodel);
            DHookSetParamString(hParams, 1, newteleportermodel);

            return MRES_ChangedHandled;
        }
    }
    
    return MRES_Ignored;
}

MRESReturn OnCalculateObjectCostPost(Address pThis, DHookReturn hReturn, DHookParam hParams) {
    int iCost = DHookGetReturn(hReturn);
    
    int builder = DHookGetParam(hParams, 1);

    int type = DHookGetParam(hParams, 2);

    int pda = GetPlayerWeaponSlot(builder, 3);
    float returncost = iCost * 1.0;
    if (IsValidEntity(pda))
    {
        if (type == 0)
        {        
            returncost = TF2CustAttr_HookValueFloatOnClient(returncost, "mod dispenser cost", builder);
        }
        else if (type == 2)
        {
            returncost = TF2CustAttr_HookValueFloatOnClient(returncost, "mod sentry cost", builder);
        }
    }

    DHookSetReturn(hReturn, RoundFloat(returncost));
    
    return MRES_ChangedOverride;
}

/////////////////////////////
// Native                  //
/////////////////////////////

int Native_BuilderHasCustomDispenser(Handle plugin, int nParams)
{
    int client = GetNativeInGameClient(1);
    
    int len;
    GetNativeStringLength(2, len);
    if(len <= 0)
    {
        return false;
    }
    char[] value = new char[len + 1];
    GetNativeString(2, value, len + 1);

    return strcmp(g_sCustomBuildingType[client][0], value) == 0;
}

int Native_BuilderHasCustomSentry(Handle plugin, int nParams)
{
    int client = GetNativeInGameClient(1);
    
    int len;
    GetNativeStringLength(2, len);
    if(len <= 0)
    {
        return false;
    }
    char[] value = new char[len + 1];
    GetNativeString(2, value, len + 1);

    return strcmp(g_sCustomBuildingType[client][1], value) == 0;
}

int Native_BuilderHasCustomTeleporter(Handle plugin, int nParams)
{
    int client = GetNativeInGameClient(1);
    
    int len;
    GetNativeStringLength(2, len);
    if(len <= 0)
    {
        return false;
    }
    char[] value = new char[len + 1];
    GetNativeString(2, value, len + 1);

    return strcmp(g_sCustomBuildingType[client][2], value) == 0;
}

int Native_DetonateObjectOfType(Handle plugin, int nParams)
{
    int client = GetNativeInGameClient(1);
    int type = GetNativeCell(2);
    int mode = GetNativeCell(3);
    bool silent = GetNativeCell(4);
    
    return SDKCall(g_SDKCallDetonateObjectOfType, client, type, mode, silent);
}

int Native_PlayerGetObjectOfType(Handle plugin, int nParams)
{
    int owner = GetNativeInGameClient(1);
    int objectType = GetNativeCell(2);
    int objectMode = GetNativeCell(3);

    return SDKCall(g_SDKCallPlayerGetObjectOfType, owner, objectType, objectMode);
}

int Native_DestroyScreens(Handle plugin, int nParams)
{
    int building = GetNativeCell(1);
    
    return SDKCall(g_SDKCallBuildingDestroyScreens, building);
}

/////////////////////////////
// Stock                   //
/////////////////////////////

stock void SetSentryRocketModel(int entity, char[] attr)
{
	if (FileExistsAndLog(attr, true))
    {
        PrecacheModelAndLog(attr);
        SetEntityModel(entity, attr);
    }
}

stock bool TF2CustAttr_ClientHasString(int client, const char[] check, char[] attr, int maxlength)
{
    for(int i = 0; i < 5; i++)
    {
        int weapon = GetPlayerWeaponSlot(client, i);
        if(IsValidEntity(weapon))
        {        
            if(TF2CustAttr_GetString(weapon, check, attr, maxlength))
            {
                return true;
            }
        }
    }

    return false;
}

stock float TF2CustAttr_HookValueFloatOnClient(float flInitial, const char[] customAttr, int iEntity, float defaultValue = 1.0)
{
    for(int i = 0; i < 5; i++)
    {
        int weapon = GetPlayerWeaponSlot(iEntity, i);
        if(IsValidEntity(weapon))
        {
            if(TF2CustAttr_GetFloat(weapon, customAttr, defaultValue) >= 0.0)
            {
                flInitial *= TF2CustAttr_GetFloat(weapon, customAttr, defaultValue);
            }
        }
    }
    
    return flInitial;
}

stock bool IsValidClient(int client, bool replaycheck=true)
{
	if(client<=0 || client>MaxClients)
		return false;

	if(!IsClientInGame(client))
		return false;

	if(GetEntProp(client, Prop_Send, "m_bIsCoaching"))
		return false;

	if(replaycheck && (IsClientSourceTV(client) || IsClientReplay(client)))
		return false;

	return true;
}

/////////////////////////////
// Utility                 //
/////////////////////////////

void UpdateBuildingInfo(int building, TFObjectType type, const char[] attr) {
    int level = GetEntProp(building, Prop_Send, "m_iUpgradeLevel");

    switch(type) {
        case TFObject_Sentry: {
            if (ReadIntVar(attr, "sentry"))
            {
                int iSentryMetalRequired[4];
                iSentryMetalRequired[0] = 0;
                iSentryMetalRequired[1] = ReadIntVar(attr, "sentry1", 200);
                iSentryMetalRequired[2] = ReadIntVar(attr, "sentry2", 400);
                iSentryMetalRequired[3] = ReadIntVar(attr, "sentry3", 600);
                
                SetEntProp(building, Prop_Send, "m_iUpgradeMetalRequired", iSentryMetalRequired[level]);
            }
        }
        case TFObject_Dispenser: {
            if (ReadIntVar(attr, "dispenser"))
            {
                int iDispenserMetalRequired[4];
                iDispenserMetalRequired[0] = 0;
                iDispenserMetalRequired[1] = ReadIntVar(attr, "dispenser1", 200);
                iDispenserMetalRequired[2] = ReadIntVar(attr, "dispenser2", 400);
                iDispenserMetalRequired[3] = ReadIntVar(attr, "dispenser3", 600);
                
                SetEntProp(building, Prop_Send, "m_iUpgradeMetalRequired", iDispenserMetalRequired[level]);
            }
        }
    }
}

bool FileExistsAndLog(const char[] path, bool use_valve_fs = false,
		const char[] valve_path_id = "GAME") {
	if (FileExists(path, use_valve_fs, valve_path_id)) {
		return true;
	}

	any discarded;
	if (!g_MissingModels.GetValue(path, discarded)) {
		LogError("Missing file '%s'", path);
		g_MissingModels.SetValue(path, true);
	}
	return false;
}

int PrecacheModelAndLog(const char[] model, bool preload = false) {
	int modelIndex = PrecacheModel(model, preload);
	if (!modelIndex) {
		LogError("Failed to precache model '%s'", model);
	}
	return modelIndex;
}

/**
 * Detonate all buildings belonging to a player
 * 
 * @param client     Player to check against
 * @param type       Type of building to destroy
 * @param mode       Mode of building to destroy
 * @param silent     Destroy buildings silently
 */
void DetonateObjectOfType(int client, int type, int mode = 0, bool silent = false) {
	SDKCall(g_SDKCallDetonateObjectOfType, client, type, mode, silent);
}