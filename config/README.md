# config/ 目录说明

本目录下的文件（providers.json、prompts.json）是项目初始架构阶段的参考/模板配置。

**这些文件不被任何场景脚本使用。** 每个测试场景（如 A1、B1、E1 等）在自己的目录下维护独立的 config.json，包含该场景所需的全部配置（providers、prompt、参数等）。

保留这些文件的目的是：创建新场景时可以参考其中的 provider 格式和 prompt 结构。
