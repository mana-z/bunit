#!/bin/bash
################################################################################
#
# Copyright 2019 Martin Zalabak
#
# This file is part of bunit.
#
# bunit is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# bunit is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with bunit.  If not, see <https://www.gnu.org/licenses/>.
#
################################################################################

# print failure
# note: not super-fast, will always add a few millis to duration
function _bUnit_failprint()
{
    local ctxlength=2 # lines of surrounding context
    local line=$1
    local origin=${BASH_SOURCE[1]}
    local before=$((line > ctxlength ? line - ctxlength : 0));
    local after=$((line + ctxlength));
    local snip=$(nl -ba -s\: $origin | sed -n "${before},${after}p")
    local clear="\e[2K\r" # empties the line
    echo -e "$clear\n$origin:$line:\n\n$snip\n" > /dev/stderr
}

# to have return in caller instead of having it buried in printing function, we
# have to have alias
shopt -s expand_aliases
alias fail='{ _bUnit_failprint $LINENO; return 1; }'


function bUnit_runAllTests() 
{
    local failures=0
    # nice colors
    local go_red="\e[31m"
    local go_green="\e[32m"
    local go_reset="\e[39m"
    # result messages
    local passed="${go_green}PASSED${go_reset}"
    local failed="${go_red}FAILED${go_reset}"
    declare -A suites # map for suites (associates suite name with string with tests)

    # results and times
    declare -A testresults
    declare -A testtimes
    # read all test names into an array
    read -a testlist <<< $(compgen -A function | grep ^test_ | tr '\n' ' ')
    # do actual tests
    for i in "${testlist[@]}"; do
        # parse suite name and test name from test function and store to suites map
        local mysuite=$(awk -F_ '{print $2}' <<< $i)
        local mytest=$(awk -F_ '{print $3}' <<< $i)
        suites[$mysuite]="${suites[$mysuite]} $mytest"

        # run suite setup if any
        type setup_$mysuite >/dev/null 2>&1
        [ $? -eq 0 ] && setup_$mysuite

        # testing...
        echo -n "$i..." > /dev/stderr
        local result
        local tic=$(date +%s%N)
        $i
        local result=$?
        local duration=$((($(date +%s%N)-$tic)/1000000)) # toc

        # interpret results
        testresults["${mysuite}_${mytest}"]=$result
        testtimes["${mysuite}_${mytest}"]=$duration
        if [ $result -eq 0 ]; then
            echo -e "$passed" > /dev/stderr
        else
            echo -e "$i...$failed" > /dev/stderr
            [ $failures -lt 255 ] && ((failures++))
        fi

        #run suite teardown if any
        type teardown_$mysuite >/dev/null 2>&1
        [ $? -eq 0 ] && teardown_$mysuite
    done

    # print results
    if [ "$1" == "xml" ]; then # xUnit xml output
        local timestamp=$(date -Iseconds | sed 's/\+.*//')
        local suiteid=0
        echo "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>"
        echo "<testsuites>"

        for i in ${!suites[@]}; do
            read -a tests <<< ${suites[$i]}

            # pulling failures and times for having it in testsuite attributes
            local failuresCount=0
            local totaltime=0
            for j in "${tests[@]}"; do
                local testcase="${i}_$j"
                local testtime=${testtimes[$testcase]}
                ((totaltime+=testtime))
                [ ! ${testresults[$testcase]} -eq 0 ] && ((failuresCount++))
            done
            local totaltime_f=$(LC_ALL=C printf "%.3f" $(bc -l <<< "$totaltime/1000"))

            echo "<testsuite"\
                "name=\"$i\""\
                "package=\"$i\""\
                "id=\"$suiteid\""\
                "hostname=\"$HOSTNAME\""\
                "tests=\"${#tests[@]}\""\
                "errors=\"0\""\
                "failures=\"$failuresCount\""\
                "time=\"$totaltime_f\""\
                "timestamp=\"$timestamp\""\
                ">"
            for j in "${tests[@]}"; do
                local time=$(LC_ALL=C printf "%.3f" $(bc -l <<< "${testtimes[${i}_$j]}/1000"))
                echo "<testcase name=\"$j\" classname=\"$i\" time=\"$time\">"
                [ ! ${testresults[${i}_$j]} -eq 0 ] && echo "<failure type=\"fail macro called\"/>"
                echo "</testcase>"
            done
            echo "</testsuite>"
            ((suiteid++))
        done
        echo "</testsuites>"

    else # pretty-print outputs
        for i in ${!suites[@]}; do
            echo -e "\nTest suite $i:"
            read -a tests <<< ${suites[$i]}
            for j in "${tests[@]}"; do
                if [ ${testresults[${i}_$j]} -eq 0 ]; then
                    result="$passed"
                else
                    result="$failed"
                fi
                echo -e "$j: $result (${testtimes[${i}_$j]} ms)"
            done
        done
        echo
    fi
    return $failures
}

