from z3 import *
import matplotlib as mpl
import matplotlib.pyplot as plt
import numpy as np

# Investigating a C4 finding for the Mute.io contest :
# Features practice using Z3
# The most relevant and time-effective stuff here was actually the curve plottings

# FUN #########################################################################
# Base calculation
def f0(l,r,w,d):
    return (l*w)/(d - (r*(d - 1)))

# Simplified calculation
def f(x):
    return 1/(2 - x)

# Reference line
def g(x):
    return 1/2 + x/2


# MOD #########################################################################
# Base model
def createModel0():
    l = Real('l')
    r = Real('r')
    w = Real('w')
    d = Real('d')

    s = Solver()
    s.add(d == 2)
    s.add(And(r > 0, r < 1))
    print("Simplification ---", end="\n")
    print(simplify(f0(l,r,w,d)))
    print("---", end="\n\n")
    return s

# Simplified model
def createModel():
    x = Real('x')
    a = Real('a')
    y = Real('y')

    s = Solver()
    s.add(x < y)
    s.add(And(x > 0, x < 1))
    s.add(And(a > 1, a < 2))
    s.add(And(y > 0, y < 1))

    # monotonicity
    s.add(f(x) < f(y))
    # homogeneity
    s.add(f(a * x) == a * f(x))
    # additivity
    s.add(f(x + y) == f(x) + f(y)) 
    
    return s

# Reference model
def createModel_g():
    x = Real('x')
    a = Real('a')
    y = Real('y')

    s = Solver()
    s.add(x < y)
    s.add(And(x > 0, x < 1))
    s.add(And(a > 1, a < 2))
    s.add(And(y > 0, y < 1))

    # monotonicity
    s.add(g(x) < g(y))
    # # homogeneity
    s.add(g(a * x) == a * g(x))
    # additivity
    s.add(g(x + y) == g(x) + g(y)) 
    
    return s


def checkModel(s):
    print("\n\n>>> MODEL :")
    print(s, end="\n\n")
    # print(s.statistics(), end="\n\n")
    if(s.check() == CheckSatResult(Z3_L_TRUE)):
        print("*** SATISFIABLE ***")
        print(s.model())
        print("*******************")
    else :
        print("### UNSATISFIABLE ###")
        print("#####################")

# PLT #########################################################################
def plot():
    x = np.linspace(-0.25, 1.25) 
    plt.figure(figsize=(5, 2.7), layout='constrained')
    plt.plot(x, f(x), label='f')
    plt.plot(x, g(x), label='g') 
    plt.xlabel('x')
    plt.ylabel('y')
    plt.grid(visible=True)
    plt.legend()
    plt.show()

# DO ##########################################################################
checkModel(createModel())
checkModel(createModel_g())
plot()
