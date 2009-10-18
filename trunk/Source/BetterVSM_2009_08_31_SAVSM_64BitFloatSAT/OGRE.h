#pragma once

//model of the warrior------------------------------------
#define WARRIOR_MESH_SOURCE L"motionblur\\Warrior.sdkmesh"
#define WARRIOR_ANIM_SOURCE L"motionblur\\Warrior.sdkmesh_anim"
//--------------------------------------------------------

//model of the windmill-----------------------------------------------
#define WINDMILL_BASE_SOURCE L"MotionBlur\\windmillstage.sdkmesh"
#define WINDMILL_FAN_SOURCE L"MotionBlur\\Fan.sdkmesh"
//--------------------------------------------------------------------

//model of the floor-------------------------------
#define PLANE_SOURCE L"plane_stone.x"
//-------------------------------------------------

//model of the static objects-----------------------
#define STATIC_OBJECT_SOURCE0 L"plane_stone.x"
#define STATIC_OBJECT_SOURCE1 L"quad_staple.x"
//-------------------------------------------------

#define MAX_BONE_MATRICES 100
#define SCALE 5.0f

#define SUIT_TECH_NAME "RenderScene"
#define BODY_TECH_NAME "RenderSkinnedScene"

#define SUIT_KERNEL_TECH_NAME "RenderSceneKernel"
#define BODY_KERNEL_TECH_NAME "RenderSkinnedSceneKernel"
#define SCENE_KERNEL_TECH_NAME "RenderHSMKernel"

#define SUIT_POS_TECH_NAME "RenderScenePos"
#define BODY_POS_TECH_NAME "RenderSkinnedScenePos"
#define SCENE_POS_TECH_NAME "RenderScreenPixelPos"

#define SUIT_DEFERRED_SHADING_TECH_NAME "RenderInputAttriTech_WarriorSuit"
#define SKIN_DEFERRED_SHADING_TECH_NAME "RenderInputAttriTech_WarriorSkin"
#define STATIC_OBJ_DEFERRED_SHADING_TECH_NAME "RenderInputAttriTech_StaticObj"


#define REVERT_NORM	;//surfNorm.x = -surfNorm.x; surfNorm.y = -surfNorm.y; surfNorm.z = -surfNorm.z;


