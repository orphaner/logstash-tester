#!/bin/bash

# Is docker installed ?
if ! hash docker 2> /dev/null; then
    error "Can't find the Docker executable. Did you install it?"
fi

usage() {
    echo "
    Logstash Tester - Unit-testing for Logstash configuration fields

    Usage:
        ./logstash-tester.sh [-bchp] -d path [test_target]

        - 'path' is the base directory for your config files and test cases.
        - 'test_target' takes one of three possible values:
            'patterns', 'filters', 'all'.
          It tells logstash-tester to runs pattern tests only,
          filter tests only or both, respectively. The default is 'all'.
          See examples for ... hum ... examples.

    Options:
    -b
        Build docker image for test
    -d
        Root directory for all your logstash config and test files.
        It is not optional and it should have a specific structure.
        See documentation for details or the 'example' directory in the
        repository root.
    -c
        Don't check the syntax of logstash configuration before running tests.
        The default is to execute 'logstash --configtest -f <config-dir>  '
        before running the tests.
    -p
        The filter tests subdirectory, inside the main test case directory.
        This allows you to run a subset of tests.
    -h
        This text.

    Examples
    ./logstash-tester.sh -d example
        The simplest command line form. Run all tests, root dir for config and
        test files is 'example'.
    ./logstash-tester.sh -d example -p syslog filters
        Run the subset of filter tests located in the 'syslog' directory
        (./test/filters/syslog).

    More info on the project repository:
        https://github.com/gaspaio/logstash-tester
    "

}

error() {
    echo "$* See help (-h) for details."
    exit 1
}

build_docker_image() {
    rootdir=$( dirname $0 )

    echo "====> Build docker image for test"
    sudo docker build -t gaspaio/logstash-tester \
        --build-arg LST=$rootdir \
        --build-arg HTTP_PROXY=$http_proxy \
        --build-arg HTTPS_PROXY=$https_proxy \
        --build-arg NO_PROXY=$no_proxy \
        -f $PWD/Dockerfile .
}

run_docker() {
    action=$1
    configtest=$2
    FILTER_CONFIG=$3
    PATTERN_CONFIG=$4
    FILTER_TESTS=$5
    PATTERN_TESTS=$6

    echo "====> Run test in docker container"
    sudo docker run --rm -it --privileged  \
        -v "${PWD}/test/spec":/test/spec/ \
        -v "${FILTER_CONFIG}":/etc/logstash/conf.d/ \
        -v "${PATTERN_CONFIG}":/opt/logstash/patterns/ \
        -v "${FILTER_TESTS}":/test/filter_data/ \
        -v "${PATTERN_TESTS}":/test/pattern_data/ \
        gaspaio/logstash-tester \
        $action $configtest
}

# Default values
action=all
configtest=y
filter_test_path=
datadir=
while getopts ":d:p:chb" opt; do
    case $opt in
        b)
            build_docker_image
            exit 0
            ;;
        d)
            if [[ -d $OPTARG ]]; then
                datadir=$OPTARG
                if [ "${DIR:0:1}" != "/" ] ; then
                    datadir=$( readlink -f $datadir)
                fi
            else
                error "'$OPTARG' is not a valid directory."
            fi
            ;;
        c)
            configtest=n
            ;;
        p)
            filter_test_path=$OPTARG
            ;;
        h)
            usage
            exit 0
            ;;
        :)
            error "Option -$OPTARG requires an argument."
            ;;
        \?)
            error "Invalid option -$OPTARG."
            ;;
    esac
done

# Handle remaining positional arguments
shift $((OPTIND-1))

if [[ -z $@ ]]; then
    action=all
elif [[ $@ != 'all' && $@ != 'filters' && $@ != 'patterns' ]]; then
    error "'$@' is not a valid action."
else
    action=$@
fi

# Handle compulsory arguments
if [[ -z $datadir ]]; then
    error "You must define a root dir for your config and test files."
fi

# Validate directories
docker_filter_config=$datadir/logstash/conf.d
if [[ ! -d $docker_filter_config ]]; then
    error "The filter config directory '$docker_filter_config' does not exist."
fi

docker_pattern_config=$datadir/logstash/patterns
if [[ ! -d $docker_pattern_config ]]; then
    error "The patterns directory '$docker_pattern_config' does not exist."
fi

docker_filter_test=$datadir/test/filters
if [[ ! -z $filter_test_path ]]; then
    docker_filter_test=$docker_filter_test/$filter_test_path
fi
if [[ ! -d $docker_filter_test ]]; then
    error "The filter tests directory '$docker_filter_test' does not exist."
fi

docker_pattern_test=$datadir/test/patterns
if [[ ! -d $docker_pattern_test ]]; then
    error "The patterns tests directory '$docker_pattern_test' does not exist."
fi

run_docker $action \
    $configtest \
    $docker_filter_config \
    $docker_pattern_config \
    $docker_filter_test \
    $docker_pattern_test

