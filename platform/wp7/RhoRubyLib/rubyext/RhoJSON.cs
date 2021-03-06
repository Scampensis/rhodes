/*------------------------------------------------------------------------
* (The MIT License)
* 
* Copyright (c) 2008-2011 Rhomobile, Inc.
* 
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
* 
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
* 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
* THE SOFTWARE.
* 
* http://rhomobile.com
*------------------------------------------------------------------------*/

using Microsoft.Scripting.Utils;
using Microsoft.Scripting.Runtime;
using IronRuby.Runtime;
using IronRuby.Builtins;
using System;
using System.Runtime.InteropServices;
using rho.common;

namespace rho.rubyext
{
    [RubyModule("Rho")]
    public static class Rho
    {
        [RubyModule("JSON")]
        public static class RhoJSON
        {
            #region Private Implementation Details

            private static RhoLogger LOG = RhoLogger.RHO_STRIP_LOG ? new RhoEmptyLogger() :
                new RhoLogger("RhoJSON");

            #endregion

            #region Private Instance & Singleton Methods

            [RubyMethodAttribute("parse", RubyMethodAttributes.PublicSingleton)]
            public static object parse(RubyModule/*!*/ self, [NotNull]string/*!*/ strData)
            {
                object res = null;
                try
                {
                    res = fastJSON.RJSONTokener.JsonDecode(strData);
                }
                catch (Exception ex)
                {
                    Exception rubyEx = self.Context.CurrentException;
                    if (rubyEx == null)
                    {
                        rubyEx = RubyExceptionData.InitializeException(new RuntimeError(ex.Message.ToString()), ex.Message);
                    }
                    LOG.ERROR("parse", ex);
                    throw rubyEx;
                }

                return res;
            }

            [RubyMethodAttribute("quote_value", RubyMethodAttributes.PublicSingleton)]
            public static object quote_value(RubyModule/*!*/ self, [NotNull]string/*!*/ strData)
            {
                object res = null;
                try
                {
                    String strRes = rho.json.JSONEntry.quoteValue(strData);
                    res = CRhoRuby.Instance.createString(strRes);
                }
                catch (Exception ex)
                {
                    Exception rubyEx = self.Context.CurrentException;
                    if (rubyEx == null)
                    {
                        rubyEx = RubyExceptionData.InitializeException(new RuntimeError(ex.Message.ToString()), ex.Message);
                    }
                    LOG.ERROR("quote_value", ex);
                    throw rubyEx;
                }

                return res;
            }

            #endregion
        }
    }
}
