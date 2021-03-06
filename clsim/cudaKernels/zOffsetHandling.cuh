/*The MIT License (MIT)

Copyright (c) 2020, Hendrik Schwanekamp hschwanekamp@nvidia.com, Ramona Hohl rhohl@nvidia.com

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGSEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

/* 
    original code to generate the z offset, ported to the cpu,
    generate a look up table for faster z-offset calculation
    Size and resolution of the look up table can be set in settings.h
*/

#ifndef ZOFFSETHANDLING_CUH
#define ZOFFSETHANDLING_CUH

// includes
// ------------------
#include "settings.cuh"
// ------------------

namespace detail {
    constexpr int tiltshiftNumDistances = 6;
    constexpr int tiltshiftNumZCoords = 125;
    constexpr float tiltshiftFirstZCoord = -5.0040000000e+02f;
    constexpr float tiltshiftZCoordSpacing = 1.0000000000e+01f;

    constexpr float tiltshiftDataFromOriginAlongTilt[tiltshiftNumDistances] = {
    -5.3141900000e+02f, -4.5488200000e+02f, 0.f, 1.6520200000e+02f, 4.4547700000e+02f, 5.2077000000e+02f,
};

    constexpr float tiltshiftZCorrections[tiltshiftNumDistances * tiltshiftNumZCoords] = {
        4.1940800000e+01f, 4.1188100000e+01f, 4.0435400000e+01f, 3.9682700000e+01f, 3.8930000000e+01f, 3.8226800000e+01f,
        3.7612800000e+01f, 3.6835500000e+01f, 3.5834400000e+01f, 3.4466000000e+01f, 3.3040500000e+01f, 3.1387800000e+01f,
        3.0063700000e+01f, 2.8294400000e+01f, 2.6889800000e+01f, 2.5276500000e+01f, 2.3713000000e+01f, 2.2398500000e+01f,
        2.1300300000e+01f, 2.0489600000e+01f, 1.9996700000e+01f, 1.9668800000e+01f, 1.9248100000e+01f, 1.8442100000e+01f,
        1.7100100000e+01f, 1.5172000000e+01f, 1.2801600000e+01f, 1.0474600000e+01f, 8.5759800000e+00f, 7.2873000000e+00f,
        6.2278000000e+00f, 5.3461300000e+00f, 4.5783900000e+00f, 3.8055300000e+00f, 3.0093500000e+00f, 2.3087200000e+00f,
        1.4637100000e+00f, 2.0222200000e-01f, -1.0952900000e+00f, -2.5619500000e+00f, -3.9427300000e+00f,
        -5.0178700000e+00f, -5.4536700000e+00f, -5.3571300000e+00f, -5.2660400000e+00f, -5.3108200000e+00f,
        -5.2127200000e+00f, -4.9138100000e+00f, -4.4959600000e+00f, -4.1450000000e+00f, -3.8552900000e+00f,
        -3.7020000000e+00f, -3.7955100000e+00f, -4.0782500000e+00f, -4.6558700000e+00f, -5.2153600000e+00f,
        -5.5854600000e+00f, -5.5321400000e+00f, -4.9599100000e+00f, -3.8815000000e+00f, -2.7985700000e+00f,
        -1.8746300000e+00f, -1.3046200000e+00f, -1.1033300000e+00f, -1.3215500000e+00f, -1.8377400000e+00f,
        -2.6842900000e+00f, -3.7756200000e+00f, -4.7011800000e+00f, -5.0942400000e+00f, -4.9680400000e+00f,
        -4.9205100000e+00f, -5.1994700000e+00f, -5.8033300000e+00f, -6.2596900000e+00f, -6.3922200000e+00f,
        -6.3200000000e+00f, -6.1547600000e+00f, -5.8214600000e+00f, -5.4075000000e+00f, -5.1543100000e+00f,
        -5.1180000000e+00f, -5.0170000000e+00f, -4.9190000000e+00f, -5.0485700000e+00f, -5.2481300000e+00f,
        -5.7312900000e+00f, -6.7902200000e+00f, -8.2558800000e+00f, -1.0060500000e+01f, -1.1956900000e+01f,
        -1.3333400000e+01f, -1.3765000000e+01f, -1.3559400000e+01f, -1.3049800000e+01f, -1.2216300000e+01f,
        -1.1407600000e+01f, -1.0610700000e+01f, -9.9209400000e+00f, -9.3718900000e+00f, -8.8414300000e+00f,
        -8.3566700000e+00f, -7.8842900000e+00f, -7.4748500000e+00f, -7.1267300000e+00f, -6.7642300000e+00f,
        -6.3565400000e+00f, -5.8549100000e+00f, -5.3322600000e+00f, -4.7218900000e+00f, -4.1681000000e+00f,
        -3.7109500000e+00f, -3.3507700000e+00f, -3.0282500000e+00f, -2.7884500000e+00f, -2.5435300000e+00f,
        -2.3059200000e+00f, -2.0915700000e+00f, -1.7749000000e+00f, -1.4882700000e+00f, -1.1612600000e+00f,
        -9.1411800000e-01f, -7.0663400000e-01f, -6.8212100000e-01f, -7.7505100000e-01f,
        // distances[0]
        3.9415100000e+01f, 3.8776800000e+01f, 3.8138500000e+01f, 3.7500200000e+01f, 3.6861900000e+01f, 3.6356800000e+01f,
        3.5825700000e+01f, 3.5064100000e+01f, 3.4135400000e+01f, 3.3062200000e+01f, 3.1928900000e+01f, 3.0467900000e+01f,
        2.9030000000e+01f, 2.7913500000e+01f, 2.6728900000e+01f, 2.5398200000e+01f, 2.4027800000e+01f, 2.2756700000e+01f,
        2.1611300000e+01f, 2.0789600000e+01f, 2.0236200000e+01f, 1.9886700000e+01f, 1.9620600000e+01f, 1.9141700000e+01f,
        1.8326600000e+01f, 1.6818200000e+01f, 1.4900200000e+01f, 1.2918100000e+01f, 1.1178300000e+01f, 9.8811100000e+00f,
        8.8585700000e+00f, 8.0278300000e+00f, 7.2214000000e+00f, 6.4912900000e+00f, 5.8097900000e+00f, 5.0789400000e+00f,
        4.3429000000e+00f, 3.4948400000e+00f, 2.4755600000e+00f, 1.2547200000e+00f, 4.1111100000e-02f, -1.0765900000e+00f,
        -1.7046900000e+00f, -1.7111800000e+00f, -1.5258800000e+00f, -1.3452500000e+00f, -1.2817600000e+00f,
        -1.1294100000e+00f, -9.3372500000e-01f, -7.4843100000e-01f, -5.3274500000e-01f, -3.9323200000e-01f,
        -4.5877600000e-01f, -7.2416700000e-01f, -1.1963200000e+00f, -1.7763200000e+00f, -2.2606200000e+00f,
        -2.4150000000e+00f, -2.2176200000e+00f, -1.4636400000e+00f, -5.7363600000e-01f, 2.5222200000e-01f,
        8.8428600000e-01f, 1.2012900000e+00f, 1.1382500000e+00f, 7.5000000000e-01f, 9.8817200000e-02f, -8.2054900000e-01f,
        -1.7420400000e+00f, -2.2720600000e+00f, -2.3550000000e+00f, -2.2848500000e+00f, -2.4189800000e+00f,
        -2.8252100000e+00f, -3.1174200000e+00f, -3.2851500000e+00f, -3.3250000000e+00f, -3.1886300000e+00f,
        -3.0068900000e+00f, -2.6572500000e+00f, -2.5528300000e+00f, -2.6709700000e+00f, -2.6086100000e+00f,
        -2.5210000000e+00f, -2.5490000000e+00f, -2.6053500000e+00f, -2.8826300000e+00f, -3.6145700000e+00f,
        -4.7631000000e+00f, -6.3781400000e+00f, -8.0304700000e+00f, -9.3966700000e+00f, -1.0182200000e+01f,
        -1.0184600000e+01f, -9.7360400000e+00f, -9.1120600000e+00f, -8.4541100000e+00f, -7.8232700000e+00f,
        -7.2681000000e+00f, -6.7795200000e+00f, -6.3338100000e+00f, -5.9020800000e+00f, -5.5068900000e+00f,
        -5.1670900000e+00f, -4.8777700000e+00f, -4.5700000000e+00f, -4.2758300000e+00f, -3.9238500000e+00f,
        -3.5176200000e+00f, -3.0930800000e+00f, -2.7055800000e+00f, -2.3797100000e+00f, -2.0847100000e+00f,
        -1.8010700000e+00f, -1.5856900000e+00f, -1.3389300000e+00f, -1.1520000000e+00f, -1.0020400000e+00f,
        -7.9549000000e-01f, -5.7294100000e-01f, -3.4058800000e-01f, -2.1411800000e-01f, -7.4000000000e-02f,
        -5.6868700000e-02f, -2.3632700000e-01f,
        // distances[1]
        0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f,
        0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f,
        0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f,
        0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f,
        0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f,
        0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f, 0.f,
        // distances[2]
        -1.8408100000e+01f, -1.7918600000e+01f, -1.7458300000e+01f, -1.7018100000e+01f, -1.6292400000e+01f,
        -1.5675600000e+01f, -1.4943400000e+01f, -1.4316100000e+01f, -1.3746100000e+01f, -1.3064300000e+01f,
        -1.2610000000e+01f, -1.2022800000e+01f, -1.1366300000e+01f, -1.0709800000e+01f, -9.9580700000e+00f,
        -9.1067000000e+00f, -8.2883500000e+00f, -7.4922200000e+00f, -6.7316800000e+00f, -6.1067900000e+00f,
        -5.6176200000e+00f, -5.2151900000e+00f, -4.9111800000e+00f, -4.6321400000e+00f, -4.2978800000e+00f,
        -3.8890500000e+00f, -3.4414300000e+00f, -2.9538100000e+00f, -2.5065400000e+00f, -2.1263100000e+00f,
        -1.7940400000e+00f, -1.4382700000e+00f, -1.0804800000e+00f, -6.9596200000e-01f, -2.9884600000e-01f,
        7.7619000000e-02f, 3.9601900000e-01f, 7.1269200000e-01f, 1.0357700000e+00f, 1.3484500000e+00f, 1.6973100000e+00f,
        2.1300000000e+00f, 2.5338500000e+00f, 2.7670000000e+00f, 2.8080000000e+00f, 2.6718400000e+00f, 2.4238800000e+00f,
        2.1667300000e+00f, 1.9936400000e+00f, 1.9148500000e+00f, 1.8754500000e+00f, 1.8680000000e+00f, 1.9191100000e+00f,
        2.0606900000e+00f, 2.1547500000e+00f, 2.3790200000e+00f, 2.6054900000e+00f, 2.7844600000e+00f, 2.8705900000e+00f,
        2.8835400000e+00f, 2.6784500000e+00f, 2.3112500000e+00f, 1.9070800000e+00f, 1.5805200000e+00f, 1.3724200000e+00f,
        1.2890000000e+00f, 1.3468300000e+00f, 1.5193200000e+00f, 1.7668900000e+00f, 2.0999000000e+00f, 2.2996100000e+00f,
        2.3560000000e+00f, 2.3340000000e+00f, 2.4181200000e+00f, 2.5488100000e+00f, 2.6003000000e+00f, 2.5800000000e+00f,
        2.5047500000e+00f, 2.4744400000e+00f, 2.2851000000e+00f, 2.0585700000e+00f, 1.9676200000e+00f, 2.0535300000e+00f,
        2.2005900000e+00f, 2.3686100000e+00f, 2.4950000000e+00f, 2.5140000000e+00f, 2.5108100000e+00f, 2.6270600000e+00f,
        2.9938100000e+00f, 3.5720600000e+00f, 4.1790600000e+00f, 4.7175000000e+00f, 5.1280600000e+00f, 5.4035300000e+00f,
        5.5201000000e+00f, 5.5050000000e+00f, 5.4200000000e+00f, 5.4552500000e+00f, 5.3855600000e+00f, 5.3209100000e+00f,
        5.3017200000e+00f, 5.1789800000e+00f, 5.0055100000e+00f, 4.8565300000e+00f, 4.6463300000e+00f, 4.4116300000e+00f,
        4.1846400000e+00f, 3.9062900000e+00f, 3.6126500000e+00f, 3.3196900000e+00f, 3.1055100000e+00f, 2.8926300000e+00f,
        2.7534700000e+00f, 2.6067700000e+00f, 2.4228600000e+00f, 2.2542400000e+00f, 2.0830600000e+00f, 1.9441400000e+00f,
        1.7524500000e+00f, 1.6077800000e+00f, 1.5440000000e+00f, 1.5480000000e+00f, 1.5027300000e+00f, 1.6427500000e+00f,
        // distances[3]
        -1.3245500000e+01f, -1.3274000000e+01f, -1.3511700000e+01f, -1.3923600000e+01f, -1.4157900000e+01f,
        -1.3961400000e+01f, -1.3306700000e+01f, -1.2520900000e+01f, -1.1525000000e+01f, -1.0513200000e+01f,
        -9.5609100000e+00f, -8.7030300000e+00f, -7.8525700000e+00f, -6.9609100000e+00f, -6.0798200000e+00f,
        -5.0436400000e+00f, -3.9395700000e+00f, -2.7030400000e+00f, -1.4542100000e+00f, -2.5660700000e-01f,
        6.8818200000e-01f, 1.4083000000e+00f, 1.8775700000e+00f, 2.1652900000e+00f, 2.2650000000e+00f, 2.3587100000e+00f,
        2.5103900000e+00f, 2.8614300000e+00f, 3.3195200000e+00f, 3.7766700000e+00f, 4.1742300000e+00f, 4.5559600000e+00f,
        5.0421500000e+00f, 5.6545300000e+00f, 6.1557100000e+00f, 6.7073600000e+00f, 7.2338100000e+00f, 7.6530800000e+00f,
        7.9092100000e+00f, 8.1569200000e+00f, 8.5396200000e+00f, 9.0113100000e+00f, 9.7300000000e+00f, 1.0405200000e+01f,
        1.0717900000e+01f, 1.0656000000e+01f, 1.0425800000e+01f, 9.8736200000e+00f, 9.2619100000e+00f, 8.7215800000e+00f,
        8.2588700000e+00f, 7.9626500000e+00f, 7.7653500000e+00f, 7.7399000000e+00f, 7.7339600000e+00f, 7.9876900000e+00f,
        8.3713500000e+00f, 8.7557100000e+00f, 9.0940800000e+00f, 9.2860000000e+00f, 9.2310300000e+00f, 8.6525800000e+00f,
        7.7607700000e+00f, 6.7637000000e+00f, 5.8816100000e+00f, 5.3196900000e+00f, 5.1570000000e+00f, 5.3173800000e+00f,
        5.6742300000e+00f, 6.2010300000e+00f, 6.9064200000e+00f, 7.2996100000e+00f, 7.3460000000e+00f, 7.2310100000e+00f,
        7.1820400000e+00f, 7.0932700000e+00f, 6.9228600000e+00f, 6.6588700000e+00f, 6.4372200000e+00f, 6.1454600000e+00f,
        5.8708200000e+00f, 5.7470000000e+00f, 5.9474800000e+00f, 6.0874300000e+00f, 6.3416500000e+00f, 6.5060000000e+00f,
        6.4698000000e+00f, 6.3087900000e+00f, 6.3399000000e+00f, 6.8896300000e+00f, 7.9291200000e+00f, 9.2317400000e+00f,
        1.0434400000e+01f, 1.1522900000e+01f, 1.2317900000e+01f, 1.2727100000e+01f, 1.2902000000e+01f, 1.2814700000e+01f,
        1.2694600000e+01f, 1.2535100000e+01f, 1.2389600000e+01f, 1.2181000000e+01f, 1.1899800000e+01f, 1.1525800000e+01f,
        1.1105800000e+01f, 1.0658400000e+01f, 1.0219600000e+01f, 9.7984200000e+00f, 9.3883300000e+00f, 9.0330900000e+00f,
        8.6622900000e+00f, 8.3403100000e+00f, 8.0473500000e+00f, 7.7695800000e+00f, 7.3810400000e+00f, 7.0093800000e+00f,
        6.6763900000e+00f, 6.2925000000e+00f, 6.0104100000e+00f, 5.6363200000e+00f, 5.3093800000e+00f, 5.1116300000e+00f,
        5.0000000000e+00f, 5.0349500000e+00f, 5.0258800000e+00f,
        // distances[4]
        -1.2580000000e+00f, -1.2224800000e+00f, -1.3575000000e+00f, -2.0852200000e+00f, -2.9345200000e+00f,
        -3.5829000000e+00f, -3.9450000000e+00f, -3.9610900000e+00f, -3.3956900000e+00f, -2.3941100000e+00f,
        -1.3351800000e+00f, -4.2740700000e-01f, 3.7587200000e-01f, 1.3146800000e+00f, 2.2790900000e+00f, 3.2083800000e+00f,
        4.1636400000e+00f, 5.2246900000e+00f, 6.4326100000e+00f, 7.7291300000e+00f, 8.8972600000e+00f, 9.9436400000e+00f,
        1.0626200000e+01f, 1.1062400000e+01f, 1.1096700000e+01f, 1.0891200000e+01f, 1.0665700000e+01f, 1.0558300000e+01f,
        1.0550800000e+01f, 1.0708200000e+01f, 1.0925100000e+01f, 1.1225100000e+01f, 1.1587500000e+01f, 1.1968500000e+01f,
        1.2453800000e+01f, 1.2965800000e+01f, 1.3486700000e+01f, 1.3958600000e+01f, 1.4331900000e+01f, 1.4524100000e+01f,
        1.4620200000e+01f, 1.5039600000e+01f, 1.5550400000e+01f, 1.6360600000e+01f, 1.7005200000e+01f, 1.7248800000e+01f,
        1.7182000000e+01f, 1.6806300000e+01f, 1.6126800000e+01f, 1.5259300000e+01f, 1.4467600000e+01f, 1.3778900000e+01f,
        1.3349800000e+01f, 1.3094600000e+01f, 1.3011200000e+01f, 1.3116400000e+01f, 1.3418600000e+01f, 1.3713300000e+01f,
        1.3964600000e+01f, 1.4272200000e+01f, 1.4318800000e+01f, 1.3920300000e+01f, 1.2961500000e+01f, 1.1684500000e+01f,
        1.0436600000e+01f, 9.5161700000e+00f, 9.0430000000e+00f, 9.0290000000e+00f, 9.2843700000e+00f, 9.6907500000e+00f,
        1.0309400000e+01f, 1.0864600000e+01f, 1.1020900000e+01f, 1.0896700000e+01f, 1.0808000000e+01f, 1.0764000000e+01f,
        1.0516600000e+01f, 1.0353700000e+01f, 1.0035200000e+01f, 9.5310400000e+00f, 9.0005300000e+00f, 8.5453100000e+00f,
        8.5230000000e+00f, 8.8215100000e+00f, 9.1569200000e+00f, 9.5202900000e+00f, 9.6158600000e+00f, 9.3990700000e+00f,
        9.2560000000e+00f, 9.6337000000e+00f, 1.0583500000e+01f, 1.1936800000e+01f, 1.3331800000e+01f, 1.4635300000e+01f,
        1.5674000000e+01f, 1.6330000000e+01f, 1.6652500000e+01f, 1.6737000000e+01f, 1.6689600000e+01f, 1.6631000000e+01f,
        1.6576500000e+01f, 1.6443300000e+01f, 1.6202200000e+01f, 1.5777900000e+01f, 1.5318500000e+01f, 1.4761600000e+01f,
        1.4168900000e+01f, 1.3564000000e+01f, 1.2956300000e+01f, 1.2360500000e+01f, 1.1782600000e+01f, 1.1260500000e+01f,
        1.0814400000e+01f, 1.0421700000e+01f, 9.9258800000e+00f, 9.4563200000e+00f, 8.9841700000e+00f, 8.4887600000e+00f,
        8.0100000000e+00f, 7.5657900000e+00f, 7.1154200000e+00f, 6.8491900000e+00f, 6.7062900000e+00f, 6.6785100000e+00f,
        6.6570000000e+00f,
        // distances[5]
    };

    float pregenerateZOffset(float nr,float z)
    {
        const float z_rescaled = (z - tiltshiftFirstZCoord) / tiltshiftZCoordSpacing;
        const int k = min(max( int(roundf(z_rescaled)), 0), tiltshiftNumZCoords - 2);

        const float fraction_z_above = z_rescaled - float(k);
        const float fraction_z_below = 1.0f - fraction_z_above;

        for (int j = 1; j < tiltshiftNumDistances; j++) {
            const float thisDist = tiltshiftDataFromOriginAlongTilt[j];
            if ((nr < thisDist) || (j == tiltshiftNumDistances - 1)) {
                const float previousDist = tiltshiftDataFromOriginAlongTilt[j - 1];
                const float thisDistanceBinWidth = thisDist - previousDist;

                const float frac_at_lower = (thisDist - nr) / thisDistanceBinWidth;
                const float frac_at_upper = 1.0f - frac_at_lower;

                const float val_at_lower =
                    (tiltshiftZCorrections[(j - 1) * tiltshiftNumZCoords + k + 1] * fraction_z_above +
                    tiltshiftZCorrections[(j - 1) * tiltshiftNumZCoords + k] * fraction_z_below);
                const float val_at_upper =
                    (tiltshiftZCorrections[j * tiltshiftNumZCoords + k + 1] * fraction_z_above +
                    tiltshiftZCorrections[j * tiltshiftNumZCoords + k] * fraction_z_below);

                return (val_at_upper * frac_at_upper + val_at_lower * frac_at_lower);
            }
        }
        return 0;
    }

}

/**
 * @brief generates a look up table for z offset values to be used with getZOffset(). 
 *          the lut needs to be uploaded to gpu memory for use on the gpu.
 * 
 */
std::vector<float> generateZOffsetLut()
{
    std::vector<float> lut(ZOLUT_NUM_ENTRIES_NR * ZOLUT_NUM_ENTRIES_Z);

    for(int i=0; i<ZOLUT_NUM_ENTRIES_NR; i++)
        for(int j=0; j<ZOLUT_NUM_ENTRIES_Z; j++)
        {
            float nr = ZOLUT_MIN_ENTRY_NR + ZOLUT_SPACING_NR * i;
            float z = ZOLUT_MIN_ENTRY_Z + ZOLUT_SPACING_Z * j;
            lut[i*ZOLUT_NUM_ENTRIES_Z + j] = detail::pregenerateZOffset(nr,z);
        }
    return lut;
}

/**
 * @brief calculates the z-offset for propagation, given a photon and the zOffset   
 * 
 * @param pos position of the photon
 * @param zOffsetLut the lut generated by generateZOffsetLut()
 * @return the z offset value that needs to be subtracted from the z-position 
 */
__device__ __forceinline__ float getZOffset(const float3& pos, const float* zOffsetLut)
{
    const int nrBin = min(max( __float2int_rd( (calcNR(pos.x, pos.y)-ZOLUT_MIN_ENTRY_NR) / ZOLUT_SPACING_NR ), 0), ZOLUT_NUM_ENTRIES_NR-1);
    const int zBin = min(max( __float2int_rd( (pos.z-ZOLUT_MIN_ENTRY_Z) / ZOLUT_SPACING_Z), 0), ZOLUT_NUM_ENTRIES_Z-1);

    return zOffsetLut[nrBin * ZOLUT_NUM_ENTRIES_Z + zBin];
}

#endif