#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

struct Control {
    vector_float3 camera;
    vector_float3 focus;
    vector_float3 light;
    int size;
    int colors;
    int bailout;
    int iterations;
    int maxRaySteps;
    float power;
    float minimumStepDistance;
    float zoom;
};

#endif /* ShaderTypes_h */

