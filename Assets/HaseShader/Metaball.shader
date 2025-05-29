Shader "Hidden/Heipu/Metaball"
{
    Properties
    {
        _MainTex ("Main Tex", 2D) = "white" {}
        _MetaballSource ("Metaball Source", 2D) = "white" {}
        _ColorRamp ("Color Ramp", 2D) = "white" {}
        _Threshold ("Threshold", float) = 0.04  // 閾値
        _LineLength ("Line Length", float) = 0.5
        _Intensity ("Intensity", float) = 1
    }

    SubShader
    {
        // No culling or depth
        Cull Off ZWrite Off ZTest Always

        HLSLINCLUDE
        // Required to compile gles 2.0 with standard srp library
        #pragma prefer_hlslcc gles
        #pragma exclude_renderers d3d11_9x

        #include "Packages/com.unity.render-pipelines.universal/Shaders/UnlitInput.hlsl"

        uniform TEXTURE2D(_MainTex);
        uniform TEXTURE2D(_MetaballSource);
        uniform SAMPLER(sampler_MainTex);
        uniform float4 _MainTex_TexelSize;

        struct Attributes
        {
            float4 positionOS : POSITION;
            float2 uv : TEXCOORD0;
        };

        struct Varyings
        {
            float2 uv : TEXCOORD0;
            float4 positionCS : SV_POSITION;
        };

        half3 Sample(float2 uv)
        {
            return SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).xyz;
        }

        half3 SampleBox(float2 uv, float delta)
        {
            float4 offset = _MainTex_TexelSize.xyxy * float2(-delta, delta).xxyy;
            half3 s =
                Sample(uv + offset.xy) + Sample(uv + offset.zy) +
                Sample(uv + offset.xw) + Sample(uv + offset.zw);
            return s * 0.25f;
        }

        Varyings PassVertex(Attributes input)
        {
            Varyings output = (Varyings)0;

            VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
            output.positionCS = vertexInput.positionCS;
            output.uv = input.uv;
            return output;
        }
        ENDHLSL

        Pass
        {
            Name "DownSampling"

            HLSLPROGRAM
            #pragma vertex PassVertex
            #pragma fragment DownSamplingPassFragment

            half4 DownSamplingPassFragment(Varyings input) : SV_Target
            {
                return half4(SampleBox(input.uv, 1), 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "UpSampling"
            Blend [_SrcBlend] [_DstBlend]

            HLSLPROGRAM
            #pragma vertex PassVertex
            #pragma fragment UpSamplingPassFragment

            half4 UpSamplingPassFragment(Varyings input) : SV_Target
            {
                return half4(SampleBox(input.uv, 0.5), 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ApplyBloom"

            HLSLPROGRAM
            #pragma vertex PassVertex
            #pragma fragment BloomPassFragment

            uniform float _Intensity;

            half4 BloomPassFragment(Varyings input) : SV_Target
            {
                half4 c = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                c.rgb += _Intensity * SampleBox(input.uv, 0.5);
                return c;
            }
            ENDHLSL
        }

        Pass
        {
            Name "ApplyMetaball"

            HLSLPROGRAM
            #pragma vertex PassVertex
            #pragma fragment BloomPassFragment

            uniform TEXTURE2D(_ColorRamp);
            uniform float _Threshold;
            uniform float _LineLength;

            half4 BloomPassFragment(Varyings input) : SV_Target
            {
                half4 c = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
                c.rgb += SampleBox(input.uv, 0.5);

                half d = c.r;
                clip(d - _Threshold);

                // TODO:
                c = lerp(c, half4(1, 1, 1, 1), step(_Threshold, d));

                // 陰の表現っぽい。アニメも表示？
                half4 ramp = SAMPLE_TEXTURE2D(_ColorRamp, sampler_MainTex, float2(d * 0.1 + _Time.y * 0.1, 0.1));

                // c = lerp(half4(1, 1, 1, 1), c, smoothstep(_Threshold - d, _Threshold - d + 0.02, 0));
                // c = lerp(ramp, c, smoothstep(_Threshold - d, _Threshold - d + 0.02, 0));
                // c = lerp(ramp, c, smoothstep(_Threshold - d, _Threshold - d + _LineLength, 0));
                c = smoothstep(_Threshold - d, _Threshold - d + _LineLength, 0);
                return c;
            }
            ENDHLSL
        }
    }
}