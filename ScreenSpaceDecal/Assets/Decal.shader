Shader "ScreenSpace/Decal"
{
    Properties
    {
        [Header(Basic)]
        [MainTexture]_MainTex("Texture", 2D) = "white" {}
        [MainColor][HDR]_Color("_Color (default = 1,1,1,1)", Color) = (1,1,1,1)
        
        [Header(Prevent Side Stretching)]
        [Toggle(_ProjectionAngleDiscardEnable)] _ProjectionAngleDiscardEnable("_ProjectionAngleDiscardEnable", float) = 0   //0 = off
        _ProjectionAngleDiscardThreshold("_ProjectionAngleDiscardThreshold", range(-1,1)) = 0
        
        [Header(Alpha remap(extra alpha control))]
        _AlphaRemap("_AlphaRemap", vector) = (1,0,0,0)
        
        [Header(Mul alpha to rgb)]
        [Toggle]_MulAlphaToRGB("_MulAlphaToRGB (default = off)", Float) = 0
        
        [Header(Stencil Masking)]
        _StencilRef("_StencilRef", Float) = 0
        [Enum(UnityEngine.Rendering.CompareFunction)]_StencilComp("_StencilComp", Float) = 0 //0 = disable

        [Header(Cull)]
        [Enum(UnityEngine.Rendering.CullMode)]_Cull("_Cull", Float) = 1 //1 = Front

        [Header(ZTest)]
        [Enum(UnityEngine.Rendering.CompareFunction)]_ZTest("_ZTest", Float) = 0 //0 = disable

        [Header(Blending)]
        [Enum(UnityEngine.Rendering.BlendMode)]_DecalSrcBlend("_DecalSrcBlend", Int) = 5 // 5 = SrcAlpha
        [Enum(UnityEngine.Rendering.BlendMode)]_DecalDstBlend("_DecalDstBlend", Int) = 10 // 10 = OneMinusSrcAlpha
    }
    SubShader
    {
        Tags { "RenderType" = "Overlay" "Queue" = "Transparent-499" "DisableBatching" = "True" }

        Pass
        {
            Stencil
            {
                Ref[_StencilRef]
                Comp[_StencilComp]
            }

            Cull[_Cull]
            ZTest[_ZTest]

            ZWrite off
            Blend[_DecalSrcBlend][_DecalDstBlend]
            
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #pragma target 3.0
            #pragma shader_feature_local_fragment _ProjectionAngleDiscardEnable
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float3 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float4 screenPos : TEXCOORD0;
                float4 viewRayOS : TEXCOORD1; // xyz: viewRayOS, w: extra copy of positionVS.z 
                float4 cameraPosOS : TEXCOORD2;
            };

            sampler2D _MainTex;
            sampler2D _CameraDepthTexture;

            CBUFFER_START(UnityPerMaterial)               
                float4 _MainTex_ST;
                float _ProjectionAngleDiscardThreshold;
                half4 _Color;
                half2 _AlphaRemap;
                half _MulAlphaToRGB;
            CBUFFER_END

            Varyings vert(Attributes v)
            {
                Varyings o = (Varyings)0;
                
                VertexPositionInputs vertexPositionInput = GetVertexPositionInputs(v.positionOS);
                o.positionCS = vertexPositionInput.positionCS;
                
                o.screenPos = ComputeScreenPos(o.positionCS);
                
                float3 viewRay = vertexPositionInput.positionVS;
                o.viewRayOS.w = viewRay.z;  //垂直方向的距离
                viewRay *= -1;
                float4x4 ViewToObjectMatrix = mul(UNITY_MATRIX_I_M, UNITY_MATRIX_I_V);
                o.viewRayOS.xyz = mul((float3x3)ViewToObjectMatrix, viewRay);
                o.cameraPosOS.xyz = mul(ViewToObjectMatrix, float4(0,0,0,1)).xyz;
                
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                i.viewRayOS.xyz /= i.viewRayOS.w;
                float2 screenSpaceUV = i.screenPos.xy / i.screenPos.w;
                float sceneRawDepth = tex2D(_CameraDepthTexture, screenSpaceUV).r;
                float3 decalSpaceScenePos;
                // perspective camera
                float sceneDepthVS = LinearEyeDepth(sceneRawDepth,_ZBufferParams);
                decalSpaceScenePos = i.cameraPosOS.xyz + i.viewRayOS.xyz * sceneDepthVS;
                // [-0.5,0.5] -> [0,1]
                float2 decalSpaceUV = decalSpaceScenePos.xy + 0.5;
                float shouldClip = 0;
#if _ProjectionAngleDiscardEnable
                float3 decalSpaceHardNormal = normalize(cross(ddx(decalSpaceScenePos), ddy(decalSpaceScenePos)));
                shouldClip = decalSpaceHardNormal.z > _ProjectionAngleDiscardThreshold ? 0 : 1;
#endif
                clip(0.5 - abs(decalSpaceScenePos) - shouldClip);
                // sample the decal texture
                float2 uv = decalSpaceUV.xy * _MainTex_ST.xy + _MainTex_ST.zw;
                half4 col = tex2D(_MainTex, uv);
                col *= _Color;// tint color
                col.a = saturate(col.a * _AlphaRemap.x + _AlphaRemap.y);// alpha remap MAD
                col.rgb *= lerp(1, col.a, _MulAlphaToRGB);
                
                return col;
            }
            ENDHLSL
        }
    }
}
