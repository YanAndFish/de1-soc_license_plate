//
//  base64.hpp
//  opencv
//
//  Created by 翎葉 on 2019/2/28.
//  Copyright © 2019 翎葉. All rights reserved.
//

#ifndef base64_hpp
#define base64_hpp

#include <stdio.h>
#include <string>

std::string base64_encode(unsigned char const* , unsigned int len);
std::string base64_decode(std::string const& s);

#endif /* base64_hpp */

