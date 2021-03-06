-- Tests of LuaDist's dependency resolving
-- Adopted from original luadist-git by mnicky.

local DependencySolver = require "rocksolver.DependencySolver"
local Package = require "rocksolver.Package"
local ordered = require "ordered"

-- Convert package list to string
local function describe_packages(pkgs)
    if not pkgs then return nil end
    assert(type(pkgs) == "table")
    local str = ""

    for k,v in ipairs(pkgs) do
        if k == 1 then
            str = str .. v.name .. "-" .. tostring(v.version)
        else
            str = str .. " " .. v.name .. "-" .. tostring(v.version)
        end
    end

    return str
end

-- Call dependency resolver - converts manifest and installed tables
-- to the required format for ease of manual definition in the tests.
local function get_dependencies(pkg, manifests, installed, platform)
    local manifest =  {repo_path = {}, packages = {}}

    local function generate_manifest(manifests)
        for _ ,current_manifest in pairs(manifests) do
            for _, pkg in pairs(current_manifest) do
                if not manifest.packages[pkg.name] then
                    manifest.packages[pkg.name] = ordered.Ordered()
                end
                manifest.packages[pkg.name][pkg.version] = {
                dependencies = pkg.deps,
                supported_platforms = type(pkg.platform) == "string" and {pkg.platform} or pkg.platform
                }
            end
        end

           return manifest
    end

    for k, v in pairs(installed) do
        installed[k] = Package(v.name, v.version, {dependencies = v.deps})
    end

    local solver = DependencySolver(generate_manifest(manifests), platform or {"unix", "linux"})
    return solver:resolve_dependencies(pkg, installed)
end


-- Return test fail message.
local function pkgs_fail_msg(pkgs, err)
    if not pkgs then
        return "TEST FAILED - Returned packages were: 'nil' \n    Error was: \"" .. (tostring(err) or "nil") .. "\""
    else
        return "TEST FAILED - Returned packages were: '" .. describe_packages(pkgs) .. "' \n    Error was: \"" .. (tostring(err) or "nil") .. "\""
    end
end

-- Run all the 'tests' and display results.
local function run_tests(tests)
    local passed = 0
    local failed = 0

    for name, test in pairs(tests) do
        local ok, err = pcall(test)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
            print("In '" .. name .. "()': " .. err)
        end
    end
    if failed > 0 then print("----------------------------------") end
    print("Passed " .. passed .. "/" .. passed + failed .. " tests (" .. failed .. " failed).")
end


-- Test suite.
local tests = {}


--- ========== DEPENDENCY RESOLVING TESTS ====================================
-- normal dependencies

-- a depends b, install a
tests.depends_1 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0-0", deps = {"b"}}
    manifest.b = {name = "b", version = "1.0-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == "b-1.0-0 a-1.0-0", pkgs_fail_msg(pkgs, err))
end

-- a depends b, b depends c, install a
tests.depends_2 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0-0", deps = {"b"}}
    manifest.b = {name = "b", version = "1.0-0", deps = {"c"}}
    manifest.c = {name = "c", version = "1.0-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == "c-1.0-0 b-1.0-0 a-1.0-0", pkgs_fail_msg(pkgs, err))
end

-- a depends b, a depends c, a depends d, c depends f, c depends g, d depends c,
-- d depends e, d depends j, e depends h, e depends i, g depends l, j depends k,
-- install a
tests.depends_3 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0-0", deps = {"b", "c", "d"}}
    manifest.b = {name = "b", version = "1.0-0"}
    manifest.c = {name = "c", version = "1.0-0", deps = {"f", "g"}}
    manifest.d = {name = "d", version = "1.0-0", deps = {"c", "e", "j"}}
    manifest.e = {name = "e", version = "1.0-0", deps = {"h", "i"}}
    manifest.f = {name = "f", version = "1.0-0"}
    manifest.g = {name = "g", version = "1.0-0", deps = {"l"}}
    manifest.h = {name = "h", version = "1.0-0"}
    manifest.i = {name = "i", version = "1.0-0"}
    manifest.j = {name = "j", version = "1.0-0", deps = {"k"}}
    manifest.k = {name = "k", version = "1.0-0"}
    manifest.l = {name = "l", version = "1.0-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == "b-1.0-0 f-1.0-0 l-1.0-0 g-1.0-0 c-1.0-0 h-1.0-0 i-1.0-0 e-1.0-0 k-1.0-0 j-1.0-0 d-1.0-0 a-1.0-0", pkgs_fail_msg(pkgs, err))
end


--- circular dependencies

-- a depends b, b depends a, install a
tests.depends_circular_1 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0-0", deps = {"b"}}
    manifest.b = {name = "b", version = "1.0-0", deps = {"a"}}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("circular"), pkgs_fail_msg(pkgs, err))
end

-- a depends b, b depends a, install a + b
tests.depends_circular_2 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0-0", deps = {"b"}}
    manifest.b = {name = "b", version = "1.0-0", deps = {"a"}}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("circular"), pkgs_fail_msg(pkgs, err))

    local pkgs, err = get_dependencies('b', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("circular"), pkgs_fail_msg(pkgs, err))
end

-- a depends b, b depends c, c depends a, install a
tests.depends_circular_3 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0-0", deps = {"b"}}
    manifest.b = {name = "b", version = "1.0-0", deps = {"c"}}
    manifest.c = {name = "c", version = "1.0-0", deps = {"a"}}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("circular"), pkgs_fail_msg(pkgs, err))
end

-- a depends b, b depends c, c depends d, d depends e, e depends b, install a
tests.depends_circular_4 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0-0", deps = {"b"}}
    manifest.b = {name = "b", version = "1.0-0", deps = {"c"}}
    manifest.c = {name = "c", version = "1.0-0", deps = {"d"}}
    manifest.d = {name = "d", version = "1.0-0", deps = {"e"}}
    manifest.e = {name = "e", version = "1.0-0", deps = {"b"}}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("circular"), pkgs_fail_msg(pkgs, err))
end


--- ========== VERSION RESOLVING TESTS  ======================================

--- check if the newest package version is chosen to install

-- a.1 & a.2 avalable, install a, check if the newest 'a' version is chosen
tests.version_install_newest_1 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "1-0"}
    manifest.a2 = {name = "a", version = "2-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == "a-2-0", pkgs_fail_msg(pkgs, err))
end

-- a depends b, b.1 & b.2 avalable, install a, check if the newest 'b' version is chosen
tests.version_install_newest_2 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0-0", deps = {"b"}}
    manifest.b1 = {name = "b", version = "1.0-0"}
    manifest.b2 = {name = "b", version = "2.0-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == "b-2.0-0 a-1.0-0", pkgs_fail_msg(pkgs, err))
end

-- provide more version types and check if the newest one is chosen to install
tests.version_install_newest_3 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "0.9-0", deps = {"b"}}
    manifest.a2 = {name = "a", version = "1.0-0", deps = {"b"}}

    manifest.b1 = {name = "b", version = "1.9-0", deps = {"c"}}
    manifest.b2 = {name = "b", version = "2.0-0", deps = {"c"}}

    manifest.c1 = {name = "c", version = "2alpha-0", deps = {"d"}}
    manifest.c2 = {name = "c", version = "2beta-0", deps = {"d"}}

    manifest.d1 = {name = "d", version = "1rc2-0", deps = {"e"}}
    manifest.d2 = {name = "d", version = "1rc3-0", deps = {"e"}}

    manifest.e1 = {name = "e", version = "3.1beta-0", deps = {"f"}}
    manifest.e2 = {name = "e", version = "3.1pre-0", deps = {"f"}}

    manifest.f1 = {name = "f", version = "3.1pre-0", deps = {"g"}}
    manifest.f2 = {name = "f", version = "3.1rc-0", deps = {"g"}}

    manifest.g1 = {name = "g", version = "1rc-0", deps = {"h"}}
    manifest.g2 = {name = "g", version = "11.0-0", deps = {"h"}}

    manifest.h1 = {name = "h", version = "1alpha2-0"}
    manifest.h2 = {name = "h", version = "1work2-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == "h-1alpha2-0 g-11.0-0 f-3.1rc-0 e-3.1pre-0 d-1rc3-0 c-2beta-0 b-2.0-0 a-1.0-0", pkgs_fail_msg(pkgs, err))
end

-- provide more version types and check if the newest one is chosen to install
tests.version_install_newest_4 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "1.1-0", deps = {"b"}}
    manifest.a2 = {name = "a", version = "2alpha-0", deps = {"b"}}

    manifest.b1 = {name = "b", version = "1.2-0", deps = {"c"}}
    manifest.b2 = {name = "b", version = "1.2beta-0", deps = {"c"}}

    manifest.c1 = {name = "c", version = "1rc3-0", deps = {"d"}}
    manifest.c2 = {name = "c", version = "1.1rc2-0", deps = {"d"}}

    manifest.d1 = {name = "d", version = "2.1beta3-0"}
    manifest.d2 = {name = "d", version = "2.2alpha2-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == "d-2.2alpha2-0 c-1.1rc2-0 b-1.2-0 a-2alpha-0", pkgs_fail_msg(pkgs, err))
end


--- check if version in depends is correctly used

tests.version_of_depends_1 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0-0", deps = {"b <= 1-0"}}

    manifest.b1 = {name = "b", version = "1.0-0", deps = {"c >= 2"}}
    manifest.b2 = {name = "b", version = "2.0-0", deps = {"c >= 2"}}

    manifest.c1 = {name = "c", version = "1.9-0", deps = {"d ~> 3.3"}}
    manifest.c2 = {name = "c", version = "2.0-0", deps = {"d ~> 3.3"}}
    manifest.c3 = {name = "c", version = "2.1-0", deps = {"d ~> 3.3"}}

    manifest.d1 = {name = "d", version = "3.2-0"}
    manifest.d2 = {name = "d", version = "3.3-0"}
    manifest.d3 = {name = "d", version = "3.3.1-0"}
    manifest.d4 = {name = "d", version = "3.3.2-0"}
    manifest.d5 = {name = "d", version = "3.4-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == "d-3.3.2-0 c-2.1-0 b-1.0-0 a-1.0-0", pkgs_fail_msg(pkgs, err))
end

tests.version_of_depends_2 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0-0", deps = {"b ~= 1.0-0"}}

    manifest.b1 = {name = "b", version = "1.0-0", deps = {"c < 2.1-0"}}
    manifest.b2 = {name = "b", version = "0.9-0", deps = {"c < 2.1-0"}}

    manifest.c1 = {name = "c", version = "2.0.9-0", deps = {"d == 4.4alpha-0"}}
    manifest.c2 = {name = "c", version = "2.1.0-0", deps = {"d == 4.4alpha-0"}}
    manifest.c3 = {name = "c", version = "2.1.1-0", deps = {"d == 4.4alpha-0"}}

    manifest.d1 = {name = "d", version = "4.0-0"}
    manifest.d2 = {name = "d", version = "4.5-0"}
    manifest.d3 = {name = "d", version = "4.4beta-0"}
    manifest.d4 = {name = "d", version = "4.4alpha-0"}
    manifest.d5 = {name = "d", version = "4.4-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == "d-4.4alpha-0 c-2.0.9-0 b-0.9-0 a-1.0-0", pkgs_fail_msg(pkgs, err))
end

tests.version_of_depends_3 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0-0", deps = {"b > 1.2-0"}}

    manifest.b1 = {name = "b", version = "1.2-0", deps = {"c ~= 2.1.1-0"}}
    manifest.b2 = {name = "b", version = "1.2alpha-0", deps = {"c ~= 2.1.1-0"}}
    manifest.b3 = {name = "b", version = "1.2beta-0", deps = {"c ~= 2.1.1-0"}}
    manifest.b5 = {name = "b", version = "1.3rc-0", deps = {"c ~= 2.1.1-0"}}
    manifest.b4 = {name = "b", version = "1.3-0", deps = {"c ~= 2.1.1-0"}}

    manifest.c1 = {name = "c", version = "2.0.9-0"}
    manifest.c3 = {name = "c", version = "2.1.1-0"}
    manifest.c2 = {name = "c", version = "2.1.0-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == "c-2.1.0-0 b-1.3-0 a-1.0-0", pkgs_fail_msg(pkgs, err))
end

tests.version_of_depends_4 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "1.0-0"}
    manifest.a2 = {name = "a", version = "2.0-0"}

    manifest.b1 = {name = "b", version = "1.0-0", deps = {"a >= 1.0"}}
    manifest.b2 = {name = "b", version = "2.0-0", deps = {"a >= 2.0"}}

    manifest.c = {name = "c", version = "1.0-0", deps = {"a ~> 1.0","b >= 1.0"}}
    manifest = {manifest}

    local pkgs, err = get_dependencies('c', manifest, installed)
    assert(describe_packages(pkgs) == "a-1.0-0 b-1.0-0 c-1.0-0", pkgs_fail_msg(pkgs, err))
end

tests.version_of_depends_5 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "1.0-0"}
    manifest.a2 = {name = "a", version = "2.0-0", deps = {"x"}}

    manifest.b = {name = "b", version = "1.0-0", deps = {"a == 1.0-0"}}

    manifest.c = {name = "c", version = "1.0-0", deps = {"a >= 1.0","b >= 1.0"}}
    manifest = {manifest}

    local pkgs, err = get_dependencies('c', manifest, installed)
    assert(describe_packages(pkgs) == "a-1.0-0 b-1.0-0 c-1.0-0", pkgs_fail_msg(pkgs, err))
end

tests.version_of_depends_8 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "1.0-0"}
    manifest.b = {name = "b", version = "1.0-0", deps = {"a 1.0-0"}}

    manifest.c = {name = "c", version = "1.0-0", deps = {"b 1.0-0"}}
    manifest = {manifest}

    local pkgs, err = get_dependencies('c', manifest, installed)
    assert(describe_packages(pkgs) == "a-1.0-0 b-1.0-0 c-1.0-0", pkgs_fail_msg(pkgs, err))
end

tests.version_of_depends_9 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "v1.0-0"}
    manifest.b = {name = "b", version = "v1.0-0", deps = {"a = v1.0-0"}}

    manifest.c = {name = "c", version = "v1.0-0", deps = {"b = v1.0-0"}}
    manifest = {manifest}

    local pkgs, err = get_dependencies('c', manifest, installed)
    assert(describe_packages(pkgs) == "a-v1.0-0 b-v1.0-0 c-v1.0-0", pkgs_fail_msg(pkgs, err))
end

tests.version_of_depends_10 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "5.1-0-0"}
    manifest.a2 = {name = "a", version = "5.2.4-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a ~> 5.2', manifest, installed)
    assert(describe_packages(pkgs) == "a-5.2.4-0", pkgs_fail_msg(pkgs, err))
end

-- TODO: Without trying all possible permutations of packages to install
-- LuaDist probably can't find a solution to this.
--[[
tests.version_of_depends_6 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "1.0"}
    manifest.a2 = {name = "a", version = "2.0"}

    manifest.b = {name = "b", version = "1.0", deps = {"a == 1.0"}}

    manifest.c = {name = "c", version = "1.0", deps = {"a >= 1.0","b >= 1.0"}}

    local pkgs, err = get_dependencies('c', manifest, installed)
    assert(describe_packages(pkgs) == "a-1.0 b-1.0 c-1.0", pkgs_fail_msg(pkgs, err))
end
--]]

-- TODO: Without trying all possible permutations of packages to install
-- LuaDist probably can't find a solution to this.
--[[
tests.version_of_depends_7 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "1.0"}
    manifest.a2 = {name = "a", version = "2.0", deps = {"d == 1.0"}}

    manifest.d1 = {name = "d", version = "1.0"}
    manifest.d2 = {name = "d", version = "2.0"}

    manifest.b = {name = "b", version = "1.0", deps = {"a == 1.0"}}

    manifest.c = {name = "c", version = "1.0", deps = {"a >= 1.0","b >= 1.0"}}

    local pkgs, err = get_dependencies('c', manifest, installed)
    assert(describe_packages(pkgs) == "a-1.0 b-1.0 c-1.0", pkgs_fail_msg(pkgs, err))
end
--]]

--- check if the installed package is in needed version

-- a-1.2 installed, b depends a >= 1.2, install b
tests.version_of_installed_1 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.2-0"}
    manifest.b = {name = "b", version = "1.0-0", deps = {"a >= 1.2-0"}}
    installed.a = manifest.a
    manifest = {manifest}

    local pkgs, err = get_dependencies('b', manifest, installed)
    assert(describe_packages(pkgs) == "b-1.0-0", pkgs_fail_msg(pkgs, err))
end

-- a-1.2 installed, a-1.3 also available, b depends a >= 1.2, install b
tests.version_of_installed_2 = function()
    local manifest, installed = {}, {}
    manifest.a12 = {name = "a", version = "1.2-0"}
    manifest.a13 = {name = "a", version = "1.3-0"}
    manifest.b = {name = "b", version = "1.0-0", deps = {"a >= 1.2-0"}}
    installed.a12 = manifest.a12
    manifest = {manifest}

    local pkgs, err = get_dependencies('b', manifest, installed)
    assert(describe_packages(pkgs) == "b-1.0-0", pkgs_fail_msg(pkgs, err))
end

-- a-1.2 installed, b depends a >= 1.4, install b
tests.version_of_installed_3 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.2-0"}
    manifest.b = {name = "b", version = "1.0-0", deps = {"a >= 1.4-0"}}
    installed.a = manifest.a
    manifest = {manifest}

    local pkgs, err = get_dependencies('b', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("but installed at version"), pkgs_fail_msg(pkgs, err))
end

-- a-1.2 installed, a-1.3 also available, b depends a >= 1.3, install b
tests.version_of_installed_4 = function()
    local manifest, installed = {}, {}
    manifest.a12 = {name = "a", version = "1.2-0"}
    manifest.a13 = {name = "a", version = "1.3-0"}
    manifest.b = {name = "b", version = "1.0-0", deps = {"a >= 1.3-0"}}
    installed.a12 = manifest.a12
    manifest = {manifest}

    local pkgs, err = get_dependencies('b', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("but installed at version"), pkgs_fail_msg(pkgs, err))
end



--- ========== OTHER EXCEPTIONAL STATES  =====================================

--- states when no packages to install are found

-- when no such package exists
tests.no_packages_to_install_1 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('x', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("No suitable candidate"), pkgs_fail_msg(pkgs, err))
end

-- when no such dependency exists
tests.no_packages_to_install_2 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0", deps = {"x"}}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("No suitable candidate"), pkgs_fail_msg(pkgs, err))
end

-- when no such dependency version exists
tests.no_packages_to_install_3 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0", deps = {"b > 1.0"}}
    manifest.b = {name = "b", version = "0.9"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("No suitable candidate"), pkgs_fail_msg(pkgs, err))
end

-- when all required packages are installed
tests.no_packages_to_install_4 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0"}
    manifest.b = {name = "b", version = "0.9"}
    installed.a = manifest.a
    installed.b = manifest.b
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == "", pkgs_fail_msg(pkgs, err))
    local pkgs, err = get_dependencies('b', manifest, installed)
    assert(describe_packages(pkgs) == "", pkgs_fail_msg(pkgs, err))
end

--- states when installed pkg is not in manifest

-- normal installed package
tests.installed_not_in_manifest_1 = function()
    local manifest, installed = {}, {}
    manifest.b = {name = "b", version = "0.9", deps = {"a"}}
    installed.a = {name = "a", version = "1.0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('b', manifest, installed)
    assert(describe_packages(pkgs) == "b-0.9", pkgs_fail_msg(pkgs, err))
end


--- ========== Platform support checking =====================================

-- no package of required platform
tests.platform_checks_1 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0", platform = "win32"}
    manifest.b = {name = "b", version = "0.9", platform = "bsd"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("No suitable candidate"), pkgs_fail_msg(pkgs, err))
    local pkgs, err = get_dependencies('b', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("No suitable candidate"), pkgs_fail_msg(pkgs, err))
end

-- no package of required platform
tests.platform_checks_2 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0", platform = "!unix"}
    manifest.b = {name = "b", version = "0.9", platform = {"bsd", "win32", "darwin"}}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("No suitable candidate"), pkgs_fail_msg(pkgs, err))
    local pkgs, err = get_dependencies('b', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("No suitable candidate"), pkgs_fail_msg(pkgs, err))
end

-- only some packages have required arch
tests.platform_checks_3 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "1.1-0", platform = "win32"}
    manifest.a2 = {name = "a", version = "1.0-0"}
    manifest.b1 = {name = "b", version = "1.9-0", platform = "bsd"}
    manifest.b2 = {name = "b", version = "0.8-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == "a-1.0-0", pkgs_fail_msg(pkgs, err))
    local pkgs, err = get_dependencies('b', manifest, installed)
    assert(describe_packages(pkgs) == "b-0.8-0", pkgs_fail_msg(pkgs, err))
end

--- ========== OS specific dependencies  =====================================

-- only OS specific dependencies
tests.os_specific_depends_1 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0", deps = {platforms = {unix = {"b", "c"}}}}
    manifest.b = {name = "b", version = "0.9"}
    manifest.c = {name = "c", version = "0.9"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed, {"unix"})
    assert(describe_packages(pkgs) == "b-0.9 c-0.9 a-1.0", pkgs_fail_msg(pkgs, err))
end

-- OS specific dependency of other platform
tests.os_specific_depends_2 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0", deps = {platforms = {win32 = {"b"}}}}
    manifest.b = {name = "b", version = "0.9"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed)
    assert(describe_packages(pkgs) == "a-1.0", pkgs_fail_msg(pkgs, err))
end

-- normal and OS specific dependencies
tests.os_specific_depends_3 = function()
    local manifest, installed = {}, {}
    manifest.a = {name = "a", version = "1.0", deps = {"c", platforms = {unix = {"b"}}, "d"}}
    manifest.b = {name = "b", version = "0.9"}
    manifest.c = {name = "c", version = "0.9"}
    manifest.d = {name = "d", version = "0.9"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a', manifest, installed, {"unix"})
    assert(describe_packages(pkgs) == "c-0.9 d-0.9 b-0.9 a-1.0", pkgs_fail_msg(pkgs, err))
end


--- ========== INSTALL SPECIFIC VERSION  =====================================

--- install specific version

-- a-1.0 available, a-2.0 available, install a-1.0
tests.install_specific_version_1 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "1.0-0"}
    manifest.a2 = {name = "a", version = "2.0-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a = 1.0-0', manifest, installed)
    assert(describe_packages(pkgs) == "a-1.0-0", pkgs_fail_msg(pkgs, err))
end

-- a-1.0 available, a-2.0 available, install a < 2.0
tests.install_specific_version_2 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "1.0-0"}
    manifest.a2 = {name = "a", version = "2.0-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a < 2.0', manifest, installed)
    assert(describe_packages(pkgs) == "a-1.0-0", pkgs_fail_msg(pkgs, err))
end

-- a-1.0 available, a-2.0 available, install a <= 2.0
tests.install_specific_version_3 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "1.0-0"}
    manifest.a2 = {name = "a", version = "2.0-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a <= 2.0-0', manifest, installed)
    assert(describe_packages(pkgs) == "a-2.0-0", pkgs_fail_msg(pkgs, err))
end

-- a-1.0 available, a-2.0 available, install a >= 3.0
tests.install_specific_version_4 = function()
    local manifest, installed = {}, {}
    manifest.a1 = {name = "a", version = "1.0-0"}
    manifest.a2 = {name = "a", version = "2.0-0"}
    manifest = {manifest}

    local pkgs, err = get_dependencies('a >= 3.0', manifest, installed)
    assert(describe_packages(pkgs) == nil and err:find("No suitable candidate"), pkgs_fail_msg(pkgs, err))
end


--- ========== INSTALL BINARY PACKAGES =====================================

-- binary a-1.0-0 available, source a-1.0-0. bin_manifest is first, so bin pkg should be installed
tests.install_binary_version_1 = function()
    local src_manifest = {}
    local bin_manifest = {}
    local installed = {}
    local manifests = {}

    src_manifest.a = {name = "a", version = "1.0-0"}
    bin_manifest.a = {name = "a", version = "1.0-0_5d4546a90e"}

    table.insert(manifests,bin_manifest)
    table.insert(manifests,src_manifest)

    local pkgs, err = get_dependencies('a == 1.0-0', manifests, installed)

    assert(describe_packages(pkgs) == "a-1.0-0_5d4546a90e", pkgs_fail_msg(pkgs, err))
end

-- binary a-1.0-0 available, source a-1.0-0. src_manifest is first, so src pkg should be installed
tests.install_source_version_1 = function()
    local src_manifest = {}
    local bin_manifest = {}
    local installed = {}
    local manifests = {}

    src_manifest.a = {name = "a", version = "1.0-0"}
    bin_manifest.a = {name = "a", version = "1.0-0_5d4546a90e",deps}

    table.insert(manifests,src_manifest)
    table.insert(manifests,bin_manifest)

    local pkgs, err = get_dependencies('a == 1.0-0', manifests, installed)

    assert(describe_packages(pkgs) == "a-1.0-0", pkgs_fail_msg(pkgs, err))
end

-- binary a-1.0-0 available, source a-1.0-0. bin_manifest is first, but dependecy isn't satisfied,
-- so src pkg is installed
tests.install_source_version_2 = function()
    local src_manifest = {}
    local bin_manifest = {}
    local installed = {}
    local manifests = {}

    src_manifest.a = {name = "a", version = "1.0-0"}
    bin_manifest.a = {name = "a", version = "1.0-0_5d4546a90e",  deps = {"b = 1.0-0"}}

    table.insert(manifests, bin_manifest)
    table.insert(manifests, src_manifest)

    local pkgs, err = get_dependencies('a == 1.0-0', manifests, installed)

    assert(describe_packages(pkgs) == "a-1.0-0", pkgs_fail_msg(pkgs, err))
end

-- binary a-1.0-0 with src dependency b-1.0-0 available. bin_manifest is first. hash isn't correct, so no pkg installed
tests.install_bad_hash_1 = function()
    local src_manifest = {}
    local bin_manifest = {}
    local installed = {}
    local manifests = {}

    src_manifest.b = {name = "b", version = "1.0-0"}
    installed.b =src_manifest.b

    bin_manifest.a = {name = "a", version = "1.0-0_abc",  deps = {"b = 1.0-0"}}

    table.insert(manifests, bin_manifest)
    table.insert(manifests, src_manifest)

    local pkgs, err = get_dependencies('a = 1.0-0', manifests, installed)
    assert(describe_packages(pkgs) == nil, pkgs_fail_msg(pkgs, err))
end

-- binary a 1.0-0 available with dependecy b ~> 1.0-0. suitable b package already installed
tests.install_suitable_hash_with_dep_1 = function()
    local src_manifest = {}
    local bin_manifest = {}
    local installed = {}
    local manifests = {}

    src_manifest.b = {name = "b", version = "1.0-7"}
    installed.b =src_manifest.b

    bin_manifest.a = {name = "a", version = "1.0-0_13f91447e9",  deps = {"b ~> 1.0"}}

    table.insert(manifests, bin_manifest)

    local pkgs, err = get_dependencies('a = 1.0-0', manifests, installed)
    assert(describe_packages(pkgs) == "a-1.0-0_13f91447e9", pkgs_fail_msg(pkgs, err))
end

-- two suitable binaries with correct hashes available. one has unsatisfied dependencies, so another is selected
tests.install_binary_version_2 = function()
    local src_manifest = {}
    local bin_manifest = {}
    local installed = {}
    local manifests = {}

    src_manifest.a = {name = "a", version = "1.0-0"}
    src_manifest.b = {name = "b", version = "1.0-0"}


    bin_manifest.d = {name = "e", version = "1.0-1_2a3d20e692",  deps = {"a","c"}}
    bin_manifest.e = {name = "e", version = "1.0-2_596a60ac84",deps= {"a","b"}}

    table.insert(manifests, bin_manifest)
    table.insert(manifests,src_manifest)

    local pkgs, err = get_dependencies('e >= 1.0', manifests, installed)
    assert(describe_packages(pkgs) == "a-1.0-0 b-1.0-0 e-1.0-2_596a60ac84", pkgs_fail_msg(pkgs, err))
end

-- two suitable binaries with correct hashes available. both have satisfied dependencies, but one's
-- dependency deps aren't satisfied,so another is selected
tests.install_binary_version_3 = function()
    local src_manifest = {}
    local bin_manifest = {}
    local installed = {}
    local manifests = {}

    src_manifest.a = {name = "a", version = "1.0-0", deps = {" b ~> 2.0"} }
    src_manifest.b = {name = "b", version = "1.0-0"}
    src_manifest.c = {name = "e", version = "1.0-0"}
    src_manifest.d = {name = "f", version = "1.0-0"}

    bin_manifest.e = {name = "g", version = "1.0-1_876c5705b7",  deps = {"e","f"}}
    bin_manifest.f = {name = "g", version = "1.0-2_1952073eb5",deps= {"a"}}

    table.insert(manifests, bin_manifest)
    table.insert(manifests,src_manifest)

    local pkgs, err = get_dependencies('g >= 1.0', manifests, installed)
    assert(describe_packages(pkgs) == "e-1.0-0 f-1.0-0 g-1.0-1_876c5705b7", pkgs_fail_msg(pkgs, err))
end
-- two suitable binaries available, all dependencies available, one depencency has wrong hash, but src version is available
tests.install_binary_version_7 = function()
    local src_manifest = {}
    local bin_manifest = {}
    local installed = {}
    local manifests = {}

    src_manifest.a = {name = "a", version = "1.0-0", deps = {"b"} }
    src_manifest.b = {name = "b", version = "1.0-0", deps = {"j"} }
    src_manifest.c = {name = "e", version = "1.0-0_a"}
    src_manifest.c = {name = "e", version = "1.0-0"}
    src_manifest.d = {name = "f", version = "1.0-0"}

    bin_manifest.e = {name = "g", version = "1.0-1_876c5705b7",  deps = {"e","f"}}
    bin_manifest.f = {name = "g", version = "1.0-2_1952073eb5",deps= {"a"}}

    table.insert(manifests, bin_manifest)
    table.insert(manifests,src_manifest)

    local pkgs, err = get_dependencies('g >= 1.0', manifests, installed)
    assert(describe_packages(pkgs) == "e-1.0-0 f-1.0-0 g-1.0-1_876c5705b7", pkgs_fail_msg(pkgs, err))
end

-- actually run the test suite
run_tests(tests)
