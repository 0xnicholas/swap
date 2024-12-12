# Notes

## Liqudity Math in Uniswap V3

```math
L=\sqrt{xy} 
```
```math
\sqrt{P}=\sqrt{\frac{y}{x}}
```
```math
L=x_{virtual} \cdot \sqrt{P}=\frac{y_{virtual}}{\sqrt{P}}
```
```math
\tag{1} (x_{real}+\frac{L}{\sqrt{P_b}})(y_{real}+L\sqrt{P_a})=L^2
```

1. Assuming $P\leq{p_a}$, the position is fully in X, so y = 0:
```math
\tag{1.1}(x+\frac{L}{\sqrt{p_b}})L\sqrt{p_a}=L^2
```
