#!/bin/bash
set +e
# Include Configuration variables 
. vnetconfig


main::set_subscription() {
    AZCLI="/usr/local/bin/az"
    main::errhandle_log_info "Setting up Active subscription to ${SUB}"
    ${AZCLI} account set --subscription "${SUB}"
    if [ $? != 0 ]; then
        main::errhandle_log_error "Unable to set active subscription ${SUB}"
    else
       local subid=$(${AZCLI} account show --query id)
       main::errhandle_log_info "Subscription ID: ${subid}"
    fi
}
main::create_resource_group() {
    main::errhandle_log_info "Creating a Resource Group ${RG}"
    ${AZCLI} group create -l ${REGION} -n ${RG} -o none 
    if [ $? != 0 ]; then
        main::errhandle_log_error "Resource Group ${RG} creation failed "
    else 
        local rgid=$(${AZCLI} group show --name ${RG} --query id)
        main::errhandle_log_info "Resource Group ID: ${rgid}"
    fi
}
main::create_vnet() {
    main::errhandle_log_info "Creating a virtual network ${VNET}"
    ${AZCLI} network vnet create -g ${RG} -n ${VNET}  --address-prefix ${VADDR} --dns-servers ${DNS} -o none
    if [ $? != 0 ]; then
        main::errhandle_log_error "Virtual Network ${VNET} creation failed "
    else 
        local vnetid=$(${AZCLI} network vnet show --name ${VNET} --resource-group ${RG} --query id)
        main::errhandle_log_info "Virtual Network ID: ${vnetid}"
    fi
}
main::create_vnet_peering() {
    main::errhandle_log_info "Creating a virtual network peering ${VNET}-to-${HUBVNET}"
    SPOKESUB=${SUB}
    SUB=${HUBSUB}
    main::set_subscription
    local remote_vnetid=$(${AZCLI} network vnet show --name ${HUBVNET} --resource-group ${HUBRG} --query id -o tsv)
    SUB=${SPOKESUB}
    main::set_subscription
    ${AZCLI} network vnet peering create -g $RG -n "${VNET}-to-${HUBVNET}" --vnet-name ${VNET}  --remote-vnet ${remote_vnetid} --allow-vnet-access --allow-forwarded-traffic --use-remote-gateway -o none
    if [ $? != 0 ]; then
        main::errhandle_log_error "Creation of virtual network peering failed "
    else 
        local vnetid=$(${AZCLI} network vnet show --name ${VNET} --resource-group ${RG} --query id -o tsv)
        local peerid=$(${AZCLI} network vnet peering show -n "${VNET}-to-${HUBVNET}" -g $RG --vnet-name ${VNET} --query id -o tsv)
        main::errhandle_log_info "Virtual Network Peer ID: ${peerid}"
        main::errhandle_log_info "Creating remote side of  network peering ${VNET}"
        SUB=${HUBSUB}
        main::set_subscription
        main::errhandle_log_info "Creating of remote network peering ${HUBVNET}"
        ${AZCLI} network vnet peering create -g ${HUBRG} -n "${HUBVNET}-to-${VNET}" --vnet-name ${HUBVNET} --remote-vnet ${vnetid}  --allow-vnet-access --allow-forwarded-traffic  --allow-gateway-transit -o none
        if [ $? != 0 ]; then
            SUB=${SPOKESUB}
            main::set_subscription
            main::errhandle_log_error "Creation of remote network peering ${HUBVNET} failed "
        else
            local remote_peerid=$(${AZCLI} network vnet peering show -n "${HUBVNET}-to-${VNET}" -g ${HUBRG} --vnet-name ${HUBVNET} --query id -o tsv)
            main::errhandle_log_info "Remote Virtual Network Peer ID: ${remote_peerid}"
            main::errhandle_log_info "Creation of remote network peering ${HUBVNET} successful "  
            SUB=${SPOKESUB}
            main::set_subscription
        fi
    fi
}
main::errhandle_log_info() {
  local log_entry=${1}
  local color="\033[1;36m"
  echo -e "${color}INFO - ${log_entry}"
}

main::errhandle_log_warning() {
  local log_entry=${1}
  local color="\033[1;33m"
  echo -e "${color}WARNING - ${log_entry}"
}

main::errhandle_log_error() {
  local log_entry=${1}
  local color="\033[1;31m"
  echo -e "${color}Error - ${log_entry}"
  main::complete error
}
main::complete () {
    local on_error=$1
    if [[ -z "${on_error}" ]]; then
        local color='\033[1;32m'
        echo -e "${color}Deployment Exited - Successful"
        #${AZCLI} account clear
        exit 0
    else
        local color="\033[1;31m"
        echo -e "${color}Deployment Exited - ERROR"
        #${AZCLI} account clear
        exit 1
    fi
}

# main functions
main::set_subscription
main::create_resource_group
main::create_vnet
main::create_vnet_peering
main::complete 
