#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void)
{
    alarm(10);
    const char *extensions[] = {VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME};
    VkApplicationInfo app = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "My Omarchy GPU probe",
        .apiVersion = VK_API_VERSION_1_2,
    };
    VkInstanceCreateInfo info = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
        .pApplicationInfo = &app,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = extensions,
    };
    VkInstance instance;
    VkResult result = vkCreateInstance(&info, NULL, &instance);
    if (result != VK_SUCCESS) {
        fprintf(stderr, "Vulkan instance unavailable (%d)\n", result);
        return 1;
    }
    uint32_t count = 0;
    int status = 1;
    if (vkEnumeratePhysicalDevices(instance, &count, NULL) != VK_SUCCESS || !count)
        goto done;
    VkPhysicalDevice *devices = calloc(count, sizeof(*devices));
    if (!devices)
        goto done;
    if (vkEnumeratePhysicalDevices(instance, &count, devices) != VK_SUCCESS) {
        free(devices);
        goto done;
    }
    for (uint32_t i = 0; i < count; i++) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(devices[i], &props);
        if (props.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU ||
            props.apiVersion < VK_API_VERSION_1_2)
            continue;
        uint32_t ext_count = 0;
        if (vkEnumerateDeviceExtensionProperties(devices[i], NULL, &ext_count, NULL) != VK_SUCCESS)
            continue;
        VkExtensionProperties *exts = calloc(ext_count, sizeof(*exts));
        if (!exts)
            continue;
        if (vkEnumerateDeviceExtensionProperties(devices[i], NULL, &ext_count, exts) == VK_SUCCESS) {
            for (uint32_t j = 0; j < ext_count; j++) {
                if (!strcmp(exts[j].extensionName, "VK_EXT_external_memory_metal")) {
                    uint32_t queue_count = 0;
                    vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &queue_count, NULL);
                    VkQueueFamilyProperties *queues = calloc(queue_count, sizeof(*queues));
                    if (!queues)
                        break;
                    vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &queue_count, queues);
                    for (uint32_t q = 0; q < queue_count; q++) {
                        if (!(queues[q].queueFlags & VK_QUEUE_GRAPHICS_BIT))
                            continue;
                        float priority = 1.0f;
                        VkDeviceQueueCreateInfo queue_info = {
                            .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                            .queueFamilyIndex = q,
                            .queueCount = 1,
                            .pQueuePriorities = &priority,
                        };
                        const char *device_extensions[] = {
                            "VK_KHR_portability_subset", "VK_EXT_external_memory_metal",
                        };
                        VkDeviceCreateInfo device_info = {
                            .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                            .queueCreateInfoCount = 1,
                            .pQueueCreateInfos = &queue_info,
                            .enabledExtensionCount = 2,
                            .ppEnabledExtensionNames = device_extensions,
                        };
                        VkDevice device;
                        if (vkCreateDevice(devices[i], &device_info, NULL, &device) == VK_SUCCESS) {
                            printf("Venus host GPU: %s\n", props.deviceName);
                            vkDestroyDevice(device, NULL);
                            status = 0;
                        }
                        break;
                    }
                    free(queues);
                    break;
                }
            }
        }
        free(exts);
        if (!status)
            break;
    }
    free(devices);
done:
    vkDestroyInstance(instance, NULL);
    return status;
}
