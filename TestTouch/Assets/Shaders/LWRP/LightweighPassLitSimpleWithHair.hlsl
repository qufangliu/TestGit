#ifndef LIGHTWEIGHT_PASS_LIT_INCLUDED
#define LIGHTWEIGHT_PASS_LIT_INCLUDED

#include "Lighting.hlsl"

struct LightweightVertexInput
{
	float4 vertex : POSITION;
	float3 normal : NORMAL;
	float4 tangent : TANGENT;
	float2 texcoord : TEXCOORD0;
	float2 lightmapUV : TEXCOORD1;
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct LightweightVertexOutput
{
	float4 uv                       : TEXCOORD0;
	DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 1);

	float4 posWSShininess           : TEXCOORD2;    // xyz: posWS, w: Shininess * 128

#ifdef _NORMALMAP
	half4 normal                    : TEXCOORD3;    // xyz: normal, w: viewDir.x
	half4 tangent                   : TEXCOORD4;    // xyz: tangent, w: viewDir.y
	half4 binormal                  : TEXCOORD5;    // xyz: binormal, w: viewDir.z
#else
	half3 normal					: TEXCOORD3;
	half3 viewDir                   : TEXCOORD4;
	half4 tangent					: TEXCOORD5;
#endif

	half4 fogFactorAndVertexLight   : TEXCOORD6; // x: fogFactor, yzw: vertex light

#ifdef _SHADOWS_ENABLED
	float4 shadowCoord              : TEXCOORD7;
#endif

	float4 clipPos                  : SV_POSITION;
	UNITY_VERTEX_INPUT_INSTANCE_ID
		UNITY_VERTEX_OUTPUT_STEREO
//HAIR


};

void InitializeInputData(LightweightVertexOutput IN, half3 normalTS, out InputData inputData)
{
	inputData.positionWS = IN.posWSShininess.xyz;

#ifdef _NORMALMAP
	half3 viewDir = half3(IN.normal.w, IN.tangent.w, IN.binormal.w);
	inputData.normalWS = TangentToWorldNormal(normalTS, IN.tangent.xyz, IN.binormal.xyz, IN.normal.xyz);
#else  
	half3 viewDir = IN.viewDir;
	inputData.normalWS = FragmentNormalWS(IN.normal);
#endif
	inputData.viewDirectionWS = FragmentViewDirWS(viewDir);
#ifdef _SHADOWS_ENABLED
	inputData.shadowCoord = IN.shadowCoord;
#else
	inputData.shadowCoord = float4(0, 0, 0, 0);
#endif
	inputData.fogCoord = IN.fogFactorAndVertexLight.x;
	inputData.vertexLighting = IN.fogFactorAndVertexLight.yzw;
	inputData.bakedGI = SAMPLE_GI(IN.lightmapUV, IN.vertexSH, inputData.normalWS);
}

///////////////////////////////////////////////////////////////////////////////
//                  Vertex and Fragment functions                            //
///////////////////////////////////////////////////////////////////////////////

// Used in Standard (Simple Lighting) shader
LightweightVertexOutput LitPassVertexSimple(LightweightVertexInput v)
{
	LightweightVertexOutput o = (LightweightVertexOutput)0;

	UNITY_SETUP_INSTANCE_ID(v);
	UNITY_TRANSFER_INSTANCE_ID(v, o);
	UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

	o.uv.xy = TRANSFORM_TEX(v.texcoord, _MainTex);
	o.uv.z = dot(UNITY_MATRIX_IT_MV[0].xyz, normalize(v.normal));
	o.uv.w = dot(UNITY_MATRIX_IT_MV[1].xyz, normalize(v.normal));
	o.uv.zw = o.uv.zw* 0.5 + 0.5;

	o.posWSShininess.xyz = TransformObjectToWorld(v.vertex.xyz);
	o.posWSShininess.w = _Shininess * 128.0;
	o.clipPos = TransformWorldToHClip(o.posWSShininess.xyz);

	half3 viewDir = VertexViewDirWS(GetCameraPositionWS() - o.posWSShininess.xyz);
	//half3 viewDir = VertexViewDirWS(GetCameraPositionWS() - );

#ifdef _NORMALMAP
	o.normal.w = viewDir.x;
	o.tangent.w = viewDir.y;
	o.binormal.w = viewDir.z;
#else
	o.viewDir = viewDir;
	o.tangent = v.tangent;
#endif

	// initializes o.normal and if _NORMALMAP also o.tangent and o.binormal
	OUTPUT_NORMAL(v, o);

	// We either sample GI from lightmap or SH.
	// Lightmap UV and vertex SH coefficients use the same interpolator ("float2 lightmapUV" for lightmap or "half3 vertexSH" for SH)
	// see DECLARE_LIGHTMAP_OR_SH macro.
	// The following funcions initialize the correct variable with correct data
	OUTPUT_LIGHTMAP_UV(v.lightmapUV, unity_LightmapST, o.lightmapUV);
	OUTPUT_SH(o.normal.xyz, o.vertexSH);

	half3 vertexLight = VertexLighting(o.posWSShininess.xyz, o.normal.xyz);
	half fogFactor = ComputeFogFactor(o.clipPos.z);
	o.fogFactorAndVertexLight = half4(fogFactor, vertexLight);

#ifdef _SHADOWS_ENABLED
#if SHADOWS_SCREEN
	o.shadowCoord = ComputeShadowCoord(o.clipPos);
#else
	o.shadowCoord = TransformWorldToShadowCoord(o.posWSShininess.xyz);
#endif
#endif

	return o;
}

// Used for StandardSimpleLighting shader
half4 LitPassFragmentSimple(LightweightVertexOutput IN) : SV_Target
{
	UNITY_SETUP_INSTANCE_ID(IN);

float2 uv = IN.uv;
half4 diffuseAlpha = SampleAlbedoAlpha(uv, TEXTURE2D_PARAM(_MainTex, sampler_MainTex));
half3 diffuse = diffuseAlpha.rgb * _Color.rgb;

half alpha = diffuseAlpha.a * _Color.a;
AlphaDiscard(alpha, _Cutoff);
#ifdef _ALPHAPREMULTIPLY_ON
diffuse *= alpha;
#endif

half3 normalTS = SampleNormal(uv, TEXTURE2D_PARAM(_BumpMap, sampler_BumpMap));
half3 emission = SampleEmission(uv, _EmissionColor.rgb, TEXTURE2D_PARAM(_EmissionMap, sampler_EmissionMap));
half4 specularGloss = SampleSpecularGloss(uv, diffuseAlpha.a, _SpecColor, TEXTURE2D_PARAM(_SpecGlossMap, sampler_SpecGlossMap));
half shininess = IN.posWSShininess.w;
half3 tangentWS = mul((float3x3)unity_ObjectToWorld, IN.tangent.xyz);
//half3 tangentWS = TransformObjectToWorldDir(IN.tangent.xyz);

//about rim light
half3 rimColor = (0.0,0.0,0.0);
#if RIM_LIGHT
half3 v = normalize(IN.viewDir);
half3 n = normalize(IN.normal);
half rim = 1 - max(0, dot(v, n));
//rim = max(0, rim);
rimColor = _RimColor * pow(rim, 1 / _RimPower);
half3 rimColor2 = _RimColor * pow(rim, 1 / _RimPower * 2);
rimColor += rimColor2;
half3 rimMask = tex2D(_RimMatcap, IN.uv.zw).rgb;
rimColor *= rimMask;
#endif

InputData inputData;
InitializeInputData(IN, normalTS, inputData);

//HAIR
#if HAIR_LIGHT
half3 T = -normalize(cross(inputData.normalWS, tangentWS));
half shift = tex2D(_ShiftMap, uv).r -_ShiftOffset;
half3 shiftT = ShiftTangent(inputData.normalWS, T, shift);
half4 hairColor = tex2D(_HairTexture, uv)*_HairColor;
#endif

#if HAIR_LIGHT
return LightweightFragmentHair(inputData, diffuse, specularGloss, shininess, emission, alpha, rimColor, shiftT, _HairRefRange, _Strength,hairColor);
#else
return LightweightFragmentBlinnPhong(inputData, diffuse, specularGloss, shininess, emission, alpha, rimColor);
#endif

};

#endif
