HAProxy Zabbix Template
=======================

### haproxy_zbx_v2_template.xml
This template is for **Zabbix 2.0**.
It has a default set of items already enbled by default but most of them are disabled.
This is meant as a starting point so you can decide which are the important ones for you.

### haproxy_zbx_v3_template.xml
This template is for **Zabbix 3.0** (and later).
It has a default set of items already enbled by default but most of them are disabled.
This is meant as a starting point so you can decide which are the important ones for you.

### haproxy_zbx_v3.4_template.xml
This template is for **Zabbix 3.4** (and later).
It takes advantage of the *Dependent Items* feature of Zabbix 3.4 to reduce the stress on the agent
retriving a full json for each discovered item and let Zabbix to parse it to get single metrics.
*This can help reducing the number of request to the agent by a factor of  about* ***30 times***.
It includes also the INFO stats for info of the whole HAProxy server.
It has a default set of items already enbled by default but most of them are disabled.
This is meant as a starting point so you can decide which are the important ones for you.

### License

[MIT License](http://opensource.org/licenses/MIT)

    The MIT License (MIT)
    
    Copyright (c) 2015 "Anastas Dancha <anapsix@random.io>"
    
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    
    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.
