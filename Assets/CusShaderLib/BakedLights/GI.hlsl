﻿#ifndef CUSTOM_GI
#define CUSTOM_GI

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"

#ifdef LIGHTMAP_ON
    #define GI_IN_DATA(NO)  float2 lightmap_uv : TEXCOORD##NO;
    #define GI_OUT_DATA float2 lightmap_uv : VAR_LIGHT_MAP_UV;
    #define TRANSFORM_GI_DATA(in, out) out.lightmap_uv = in.lightmap_uv * unity_LightmapST.xy + unity_LightmapST.zw;
    #define GI_FRAGMENT_DATA(in) in.lightmap_uv
    #define COPY_GI_DATA(in, out) out.lightmap_uv = in.lightmap_uv;
#else
    #define GI_IN_DATA(NO)
    #define GI_OUT_DATA 
    #define TRANSFORM_GI_DATA(in, out) 
    #define GI_FRAGMENT_DATA(in) 0.0
    #define COPY_GI_DATA(in, out) 
#endif

TEXTURE2D(unity_Lightmap);
SAMPLER(samplerunity_Lightmap);
TEXTURE3D_FLOAT(unity_ProbeVolumeSH);
SAMPLER(samplerunity_ProbeVolumeSH);
TEXTURE2D(unity_ShadowMask);
SAMPLER(samplerunity_ShadowMask);
TEXTURECUBE(unity_SpecCube0);
SAMPLER(samplerunity_SpecCube0);

struct GI
{
    float3 diffuse;
    float3 specular;
    ShadowMask shadow_mask;
};

float3 SampleEnviroment(Surface surface, BRDF brdf)
{
    float3 uvw = reflect(-surface.view_dir, surface.normal_ws);
    float mip = PerceptualRoughnessToMipmapLevel(brdf.perceptual_roughness);
    float4 enviroment = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, uvw, mip);
    return DecodeHDREnvironment(enviroment, unity_SpecCube0_HDR);
}


float3 SampleLightMap(float2 lightmap_uv, float3 normal)
{
    #ifdef DIRLIGHTMAP_COMBINED
        return SampleDirectionalLightmap(TEXTURE2D_ARGS(unity_Lightmap, samplerunity_Lightmap),
        TEXTURE2D_ARGS(unity_LightmapInd, samplerunity_Lightmap),
        lightmap_uv, float4(1.0, 1.0, 0.0, 0.0), normal,  
        #ifdef UNITY_LIGHTMAP_FULL_HDR
            false,
        #else
            true,
        #endif 
        float4(LIGHTMAP_HDR_MULTIPLIER, LIGHTMAP_HDR_EXPONENT, 0.0, 0.0));

    #elif LIGHTMAP_ON
        return SampleSingleLightmap(TEXTURE2D_ARGS(unity_Lightmap, samplerunity_Lightmap), lightmap_uv, float4(1.0, 1.0, 0.0, 0.0),
        #ifdef UNITY_LIGHTMAP_FULL_HDR
            false,
        #else
            true,
        #endif
        float4(LIGHTMAP_HDR_MULTIPLIER, LIGHTMAP_HDR_EXPONENT, 0.0, 0.0));
    #else
        return 0.0f;
    #endif
}

float3 SampleLightProbes(Surface surface)
{
    #ifdef LIGHTMAP_ON
        return 0.0;
    #else
        if(unity_ProbeVolumeParams.x)
        {
            return SampleProbeVolumeSH4(TEXTURE3D_ARGS(unity_ProbeVolumeSH, samplerunity_ProbeVolumeSH), surface.pos_ws, surface.normal_ws, 
            unity_probeVolumeWorldToObject,
            unity_ProbeVolumeParams.y, unity_ProbeVolumeParams.z,
            unity_ProbeVolumeMin.xyz, unity_ProbeVolumeSizeInv.xyz);

        }
        else
        {
            float4 coefficient[7];
            coefficient[0] = unity_SHAr;
            coefficient[1] = unity_SHAg;
            coefficient[2] = unity_SHAb;
            coefficient[3] = unity_SHBr;
            coefficient[4] = unity_SHBg;
            coefficient[5] = unity_SHBb;
            coefficient[6] = unity_SHC;
            return max(0.0f, SampleSH9(coefficient, surface.normal_ws));
        }
        
    #endif
}

float4 SampleBakedShadows(Surface surface)
{
    #if defined(LIGHTMAP_ON)
        return SAMPLE_TEXTURE2D(unity_ShadowMask, samplerunity_ShadowMask, surface.lightmap_uv);
    #else
        if(unity_ProbeVolumeParams.x)
        {
                return SampleProbeOcclusion(
				TEXTURE3D_ARGS(unity_ProbeVolumeSH, samplerunity_ProbeVolumeSH),
				surface.pos_ws, 
                unity_probeVolumeWorldToObject,
				unity_ProbeVolumeParams.y, unity_ProbeVolumeParams.z,
				unity_ProbeVolumeMin.xyz, unity_ProbeVolumeSizeInv.xyz
			);
        }
        else
        {
            return unity_ProbesOcclusion;
        }
    #endif
}

GI GetGI(Surface surface, BRDF brdf)
{
    GI gi;
    gi.diffuse = SampleLightMap(GI_FRAGMENT_DATA(surface), surface.normal_ws) + SampleLightProbes(surface);
    gi.specular = SampleEnviroment(surface, brdf);
    gi.shadow_mask.distance = false;
    gi.shadow_mask.shadows = 1.0;
    gi.shadow_mask.always = false;
    #if defined(_SHADOW_MASK_ALWAYS)
        gi.shadow_mask.always = true;
        gi.shadow_mask.shadows = SampleBakedShadows(surface);
    #elif defined(_SHADOW_MASK_DISTANCE)
        gi.shadow_mask.distance = true;
        gi.shadow_mask.shadows = SampleBakedShadows(surface);
    #endif
    return gi;
}
#endif