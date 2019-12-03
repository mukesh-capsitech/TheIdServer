﻿using Aguacongas.IdentityServer.Store.Entity;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

namespace Aguacongas.IdentityServer.Admin
{
    /// <summary>
    /// Utils class
    /// </summary>
    public static class Utils
    {
        /// <summary>
        /// Gets the entity type list.
        /// </summary>
        /// <returns></returns>
        public static IEnumerable<Type> GetEntityTypeList()
        {
            var assembly = typeof(IEntityId).GetTypeInfo().Assembly;
            var entyTypeList = assembly.GetTypes().Where(t => t.IsClass &&
                !t.IsAbstract &&
                t.GetInterface("IEntityId") != null);
            return entyTypeList;
        }
    }
}
